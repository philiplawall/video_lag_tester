`include "defines.v"


module lagtester(
    input clock,

    
    input SENSOR,
    input [1:0] KEY, // push buttons on the board, active low

    output wire        O_tmds_clk_p,
    output wire        O_tmds_clk_n,
    output wire [2:0]  O_tmds_data_p,
    output wire [2:0]  O_tmds_data_n,

    output wire LED
);
    wire internal_clock;
    
    wire sensor_out;
    wire sensor_trigger;

    wire reset_statistics;
    wire [7:0] config_data;

    wire starttrigger;
    wire reset_counter;
    wire [7:0] config_data_crossed;
    wire [79:0] bcdcount_crossed;
    wire [19:0] bcd_current;
    wire [19:0] bcd_minimum;
    wire [19:0] bcd_maximum;
    wire [19:0] bcd_average;

    wire tfp410_ready;
    wire hpd_detected;

wire clk_serial;
wire hdmi_rstn;

    wire [7:0] DVI_RED;
    wire [7:0] DVI_GREEN;
    wire [7:0] DVI_BLUE;
    wire DVI_DE;
    wire DVI_HSYN;
    wire DVI_VSYNC;

    ///////////////////////////////////////////
    // clocks

`define PIXEL_CLOCK_135 4'd3
`define PIXEL_CLOCK_371_25 4'd2
video_clock video_clock_inst (
  .clk27       (clock), 
  .clock_config(`PIXEL_CLOCK_371_25),
  .rstn        (1'b1),
  .hdmi_rstn_o (hdmi_rstn),
  .clk_serial  (clk_serial),
  .clk_pixel   (internal_clock)
);

hdmi_device hdmi_device (
    .I_rst_n       (hdmi_rstn         ),
    .I_serial_clk  (clk_serial        ),
    .I_rgb_clk     (internal_clock    ),
    .I_rgb_vs      (DVI_VSYNC ),
    .I_rgb_hs      (DVI_HSYNC ),
    .I_rgb_de      (DVI_DE    ),

     //.I_rgb_r       ({DVI_RED[7] ? 8'hff : 8'h11}),
     //.I_rgb_g       ({DVI_GREEN[7] ? 8'hff : 8'h11}),
     //.I_rgb_b       ({DVI_BLUE[7] ? 8'hff : 8'h11}),

     .I_rgb_r       (DVI_RED),
     .I_rgb_g       (DVI_GREEN),
     .I_rgb_b       (DVI_BLUE),
    .O_tmds_clk_p  (O_tmds_clk_p      ),
    .O_tmds_clk_n  (O_tmds_clk_n      ),
    .O_tmds_data_p (O_tmds_data_p     ),
    .O_tmds_data_n (O_tmds_data_n     )
);
    ///////////////////////////////////////////
    // sensor
    sensor sensor(
        .clock(clock),
        .sensor(SENSOR),
        .sensor_out(sensor_out),
        .sensor_trigger(sensor_trigger)
    );

    ///////////////////////////////////////////
    // buttons (active low, internal pull-up)
    //   KEY[0]: toggle the measuring range
    //           fine:   lag < 333 ms, display XXX.XX ms
    //           coarse: lag < 2.5 s,  display XXXX.X ms
    //   KEY[1]: reset min / max / average
    wire key_range_pressed;
    wire key_reset_pressed;
    reg range_coarse = 1'b0;

    button_input button_range(
        .clock(clock),
        .button_n(KEY[0]),
        .pressed(key_range_pressed)
    );

    button_input button_reset(
        .clock(clock),
        .button_n(KEY[1]),
        .pressed(key_reset_pressed)
    );

    always @(posedge clock) begin
        if (key_range_pressed) begin
            range_coarse <= ~range_coarse;
        end
    end

    // a range change invalidates min / max / average
    assign reset_statistics = key_range_pressed | key_reset_pressed;

    // The range bit is sent to the video clock domain through the config
    // byte (data_cross below only transfers on change). startup_done forces
    // one transfer shortly after power up so both domains agree on the
    // range before the first key press.
    reg [19:0] startup_counter = 0;
    reg startup_done = 1'b0;

    always @(posedge clock) begin
        if (&startup_counter) begin
            startup_done <= 1'b1;
        end else begin
            startup_counter <= startup_counter + 1'b1;
        end
    end

    assign config_data = { 6'b0, startup_done, range_coarse };

    ///////////////////////////////////////////
    // measurement
    Flag_CrossDomain reset_control(
        .clkA(internal_clock),
        .FlagIn_clkA(starttrigger),
        .clkB(clock),
        .FlagOut_clkB(reset_counter)
    );

    measure measure(
        .clock(clock),
        .reset_counter(reset_counter),
        .sensor_trigger(sensor_trigger),
        .reset_bcdoutput(reset_statistics),
        .range_coarse(range_coarse),
        .bcd_current(bcd_current),
        .bcd_minimum(bcd_minimum),
        .bcd_maximum(bcd_maximum),
        .bcd_average(bcd_average)
    );

    ///////////////////////////////////////////
    // video generator
    data_cross #(
        .WIDTH(8)
    ) video_data_cross (
        .clkIn(clock),
        .clkOut(internal_clock),
        .dataIn(config_data),
        .dataOut(config_data_crossed)
    );

    data_cross #(
        .WIDTH(80)
    ) bcdcounter_cross (
        .clkIn(clock),
        .clkOut(internal_clock),
        .dataIn({ bcd_average, bcd_maximum, bcd_minimum, bcd_current }),
        .dataOut(bcdcount_crossed)
    );

    video video(

        .clock(internal_clock),
        .config_data(config_data_crossed),
        .bcdcount(bcdcount_crossed),
        .red(DVI_RED),
        .green(DVI_GREEN),
        .blue(DVI_BLUE),
        .de(DVI_DE),
        .hsync(DVI_HSYNC),
        .vsync(DVI_VSYNC),
        .starttrigger(starttrigger)
    );
    ///////////////////////////////////////////




reg         vs_r;
reg  [9:0]  cnt_vs;


always@(posedge internal_clock) begin
  vs_r <= DVI_VSYNC;
end
always@(posedge internal_clock) begin
    if(vs_r && !DVI_VSYNC) //vs falling edge
        cnt_vs <= cnt_vs + 10'd1;
end

 //assign LED = cnt_vs[6];

 assign LED = sensor_out;
 //   assign TFP410_reset = 1'b1;

endmodule
