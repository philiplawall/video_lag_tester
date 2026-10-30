/*
    Push button input: synchronizer, debounce and press detection.

    button_n is active low (the Tang Nano 4K keys pull the pin to GND, the
    internal pull-up is enabled in the constraints file). pressed is high for
    one clock cycle after the debounced button went down; holding the button
    does not repeat.
*/
module button_input(
    input clock,
    input button_n,
    output reg pressed
);
    // 20 ms at 27 MHz
    parameter DEBOUNCE_CYCLES = 540000;

    reg [2:0] sync = 3'b111;
    reg stable = 1'b0;
    reg [19:0] debounce = 0;

    wire raw = ~sync[2];

    always @(posedge clock) begin
        sync <= { sync[1:0], button_n };
        pressed <= 1'b0;
        if (raw == stable) begin
            debounce <= 0;
        end else if (debounce == DEBOUNCE_CYCLES - 1) begin
            debounce <= 0;
            stable <= raw;
            pressed <= raw;
        end else begin
            debounce <= debounce + 1'b1;
        end
    end

endmodule
