# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Firmware for a low-cost HDMI video lag tester on the **Sipeed Tang Nano 4K** (Gowin GW1NSR-LV4CQN48PC6/I5). The FPGA outputs a 720p60 HDMI signal with flashing white test fields, a phototransistor on the display detects when the field appears, and the measured delay (current / min / max / average) is rendered as text on the same HDMI output. The two board keys toggle the measuring range (fine, up to 333 ms, or coarse, up to 2.5 s) and reset the statistics. The measurement logicis ported from [Time Sleuth](https://github.com/chriz2600/time-sleuth) (Altera/TFP410 hardware); the HDMI/TMDS output and clocking come from Sipeed's Tang Nano 4K HDMI demo.

There is no software component, no test suite, and no CI. Everything is Verilog/SystemVerilog plus a Gowin project file.

## Building and flashing

**Toolchain:** Gowin FPGA Designer **1.9.8.03 Education** (GUI). Open `hdmi_out_time_sleuth/hdmi_out.gprj`, then run Synthesize → Place & Route. Output bitstream lands at `hdmi_out_time_sleuth/impl/pnr/hdmi_out.fs`. The `impl/` directory is not tracked and there is no `.gitignore`, so don't commit it.

The sources use SystemVerilog constructs (`package`, `typedef struct packed`, `const`, `import`, `task`) despite the `.v` extension, so the project's synthesis language setting must be SystemVerilog.

**Flash (no driver needed, USB-C):**
```
openFPGALoader -b tangnano4k -f hdmi_out_time_sleuth/impl/pnr/hdmi_out.fs
```
Release zips also ship a `load_720p.cmd` for Windows; neither it nor the `firmware/` folder is in this repo.

There is no Makefile, Tcl build script, or simulation testbench.

## Which files are actually built

The `.gprj` file list is the source of truth, and it is a subset of what's checked in. Files tracked but **not** in the project (legacy from Time Sleuth or the Sipeed demo, kept for reference):

- `src/time_sleuth/pll/` — Altera PLL reconfiguration (`.qip`, `.mif`); Gowin uses `src/video_clock.v` instead.
- `src/time_sleuth/tfp410/` — I2C setup for the TFP410 DVI transmitter; Tang Nano 4K drives TMDS directly.
- `src/time_sleuth/generated/` — references 576p/288p modes that don't exist in this port.
- `src/time_sleuth/misc/data_fifo.v`, `delayline.v` — replaced by the Gowin `FIFO_HS` IP.
- `src/video_top.v` — the original Sipeed test-pattern top; present in the `.gprj` but `enable="0"`.
- `src/dk_video_fp.cst` — same pins as `dk_video.cst` plus a floorplanner `GROUP` placement constraint; not enabled.

**Top module is `lagtester`** (`src/time_sleuth/lagtester.v`). The GAO (logic analyzer) config in `src/hdmi_out.gao` also targets it.

## Architecture

### Two clock domains

| Domain | Source | Runs |
|---|---|---|
| `clock` 27 MHz | board oscillator, pin 45 | `sensor`, `configuration`, `measure` |
| `internal_clock` 74.25 MHz pixel clock | `video_clock` (PLL ÷5 of 371.25 MHz serial) | `video` and everything under it, HDMI encoder |

`video_clock.v` builds the pixel clock from two `PLLVR` instances, a `DCS` clock mux, and a `CLKDIV` by 5; the `clock_config` input selects among 126/135/200/325/371.25 MHz serial rates. 1080p is commented as "not working yet" in `video_timing.vh`.

Crossings between domains go through `misc/Flag_CrossDomain.v` (single pulse: `starttrigger` → `reset_counter`) and `misc/data_cross.v` (buses: config byte and the 80-bit BCD results, via one `FIFO_HS_Top` per byte). A third pseudo-clock, `measure/counter_trigger` (27 MHz ÷ `CLOCK_DIVIDER`=27 → 1 µs ticks), clocks the ripple `bcdcounter`; `dk_video.sdc` declares all three asynchronous.

### Measurement loop

1. `video/videogen.v` counts frames. Every `FRAME_COUNTER` (20) frames in the fine range, or `FRAME_COUNTER_COARSE` (150) in the coarse range, it pulses `starttrigger` and turns on three white test fields (`h_field_*`/`v_field*` in the `VideoMode` struct) for `FRAME_ON_COUNT` (15) frames. A `metaCounter` adds 0–7 frames of jitter so the flash isn't phase-locked to the display. The lag must be shorter than the flash period; a longer lag doesn't saturate, it aliases (reads as lag minus one period).
2. `measure.v` resets the microsecond BCD counter on `starttrigger`, then latches it on the first `sensor_trigger` (rising edge of the inverted, active-low phototransistor input). The counter has 7 BCD digits (`misc/bcdcounter.v`); `range_coarse` picks which 5 are displayed: 10 µs steps (`XXX.XX ms`) or 100 µs steps (`XXXX.X ms`). The average path is binary (22 bits) and converted with `Binary_to_BCD`, same digit selection. Min/max reset at the start of each 16-sample averaging window (`AVERAGE_BITS`=4). Results are 20-bit BCD each; `MAX_BCDCOUNT` (99999) means "no reading yet" and the text generator skips those digits.
3. The 80-bit `{avg, max, min, current}` bundle crosses to the pixel domain and `video/textgen.v` writes it into the on-screen text.

The on-board LED mirrors the inverted sensor input, which is a quick way to check the phototransistor without a display.

### Buttons

`lagtester.v` debounces the two board keys with `misc/button_input.v` (27 MHz domain, 20 ms). KEY[0] toggles `range_coarse`, KEY[1] resets the statistics; either press drives `measure`'s `reset_bcdoutput`, which `measure.v` latches as pending if it collides with a counter restart. The range bit reaches the pixel domain through the existing 8-bit `config_data` crossing: bit 0 is the range, bit 1 is a startup flag that forces one transfer about 39 ms after power-up so both domains agree before the first key press (the FIFO IP is encrypted, so its power-up output can't be checked). Time Sleuth's DIP-switch module `configuration.v` is still in the project file list but no longer instantiated.

### Video mode is hard-wired

Time Sleuth selected resolution from DIP switches via `configuration.v` → `video/video_config.v`. That path is gone here:

- `video.v` assigns `videoMode = VIDEO_MODE_720P` directly (the `video_config` instance is commented out).
- `lagtester.v` hard-codes `clock_config` to `PIXEL_CLOCK_371_25`.

To change resolution you must change **both** the `VideoMode` constant in `video.v` and the pixel-clock selection in `lagtester.v`, and update the `clk_serial` period in `dk_video.sdc` (currently 2.694 ns = 371.25 MHz). Mode timings live in `time_sleuth/config/video_modes.v` as `const VideoMode` structs defined by `typedef.v`; the struct carries both HDMI timing and the on-screen layout (test-field rectangles, text position, and `h_/v_*_divider` pixel-doubling shifts). Interlaced modes use the `*_1`/`*_2` field pairs toggled by `timingsgen`'s `state` bit.

### On-screen text pipeline

`textgen.v` assembles one 512-bit scanline (`LAGLINE_SIZE`) per row at the start of each line (`counterX` 0–3 triggers a 37-step state machine): it starts from a static label bitmap (`char_rom/font/predef/lagdisplay.v`, generated by `char_rom/font/string-to-pixels.py` from `8x16-font.v`) and overlays digits looked up in `char_rom/char_rom.v` (`8x16-font-digits.v`: 10 glyphs × 16 rows, address = `digit << 4 | row`). Bit offsets in `textgen.v` (e.g. `[319:312]`, `[199:192]`) are hand-placed to line up with the label text; `videogen.v` slices the same line at `-80`, `-200`, `-392` horizontal offsets for the four text rows. Each value has 6 slots with the decimal point baked into the bitmap at slot 4; in the coarse range `textgen` writes the second digit over that slot and a point glyph (`dot_row`, one pixel at row 12) into slot 5. `char_rom/resolution.v` draws the resolution label at top-right by muxing on `videoMode.id` bits.

### Include paths

`` `include `` directives are inconsistent: some are relative to `src/` (`"time_sleuth/defines.v"`), some to the including file (`"../defines.v"`), and most are bare (`"defines.v"`, `"video_modes.v"`), relying on Gowin's include search. If you add a file, follow whichever style its sibling uses and verify in the GUI that synthesis still resolves it.

## Pinout (`src/dk_video.cst`)

TMDS clock on pins 27/28, data on 29–35, LED on pin 10, SENSOR on pin 44 (internal pull-up, active low), 27 MHz clock on pin 45, KEY[0] on pin 14 and KEY[1] on pin 15 (internal pull-up, active low, same assignment as Sipeed's `key_blink` example).
