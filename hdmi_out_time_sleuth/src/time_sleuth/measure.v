`include "defines.v"

module measure(
    input clock,
    input reset_counter,
    input sensor_trigger, // ~prev_sensor_input && sensor_input
    input reset_bcdoutput, // button pressed or measuring range changed
    input range_coarse, // 0: 10 us display steps, 1: 100 us display steps

    output [19:0] bcd_current,
    output [19:0] bcd_minimum,
    output [19:0] bcd_maximum,
    output [19:0] bcd_average
);
    wire [27:0] bcdcount;
    wire [27:0] avg_counter_bcd;
    wire avg_counter_ready;

    reg waiting;
    reg [8:0] counter;
    reg [24:0] raw_counter;
    reg counter_trigger = 0;
    reg reset_bcdcounter = 0;
    reg reset_bcdoutput_pending = 0;
    reg [19:0] bcdcount_out = `MAX_BCDCOUNT;
    reg [19:0] bcdcount_min = `MAX_BCDCOUNT;
    reg [19:0] bcdcount_max = 0;
    reg [21:0] avg_counter;
    reg [31:0] avg_counter_reg;
    reg [31:0] avg_counter_reg_avg;
    reg [19:0] avg_counter_bcd_reg = `MAX_BCDCOUNT;
    reg avg_counter_start;
    reg [`AVERAGE_BITS-1:0] avg_loop;

    /*
        The counters tick every 1 us and have 7 BCD digits (max 9.999999 s),
        but only 5 digits are displayed. The measuring range selects which:
            fine:   digits 2..6, 10 us steps  -> "XXX.XX ms", max 999.99 ms
            coarse: digits 3..7, 100 us steps -> "XXXX.X ms", max 9999.9 ms
    */
    wire [19:0] bcdcount_display = range_coarse ? bcdcount[27:8] : bcdcount[23:4];
    wire [19:0] avg_counter_bcd_display = range_coarse ? avg_counter_bcd[27:8] : avg_counter_bcd[23:4];

    bcdcounter bcdcounter(
        .trigger(counter_trigger),
        .reset(reset_bcdcounter),
        .bcdcount(bcdcount)
    );

    Binary_to_BCD #(
        .INPUT_WIDTH(22),
        .DECIMAL_DIGITS(7)
    ) Binary_to_BCD (
        .i_Clock(clock),
        .i_Start(avg_counter_start),
        .i_Binary(avg_counter_reg_avg[21:0]),
        .o_BCD(avg_counter_bcd),
        .o_DV(avg_counter_ready)
    );

    /* 
        create trigger for the bcd counter,
        27MHz / 27, so trigger every 0.001 ms
    */
    always @(posedge clock) begin
        if (reset_counter) begin
            raw_counter <= 0;
            counter <= 0;
            counter_trigger <= 0;
            reset_bcdcounter <= 1;
        end else begin
            raw_counter <= raw_counter + 1'b1;
            reset_bcdcounter <= 0;
            if (counter < `CLOCK_DIVIDER - 1) begin
                counter <= counter + 1'b1;
                counter_trigger <= 0;
            end else begin
                counter <= 0;
                counter_trigger <= 1;
            end
        end
    end

    ///////////////////////////////////////////////////////

    always @(posedge counter_trigger or posedge reset_bcdcounter) begin
        if (reset_bcdcounter) begin
            avg_counter <= 0;
        end else begin
            avg_counter <= avg_counter + 1'b1;
        end
    end

    ///////////////////////////////////////////////////////

    always @(posedge clock) begin
        if (reset_counter) begin
            waiting <= 1;
            // remember a reset request that arrives while the counter is
            // being restarted, so a button press is never lost
            if (reset_bcdoutput) begin
                reset_bcdoutput_pending <= 1;
            end
        end else if (reset_bcdoutput || reset_bcdoutput_pending) begin
            reset_bcdoutput_pending <= 0;
            bcdcount_out <= `MAX_BCDCOUNT;
            bcdcount_max <= 0;
            bcdcount_min <= `MAX_BCDCOUNT;
            avg_counter_reg_avg <= 0;
            avg_counter_reg <= 0;
            avg_loop <= 0;
            avg_counter_bcd_reg <= `MAX_BCDCOUNT;
        end else if (waiting && sensor_trigger) begin
            bcdcount_out <= bcdcount_display;
            if (avg_loop == 0) begin
                // reset min and max at the start of the averaging period
                bcdcount_max <= bcdcount_display;
                bcdcount_min <= bcdcount_display;
            end else begin
                if (bcdcount_display < bcdcount_min) begin
                    bcdcount_min <= bcdcount_display;
                end
                if (bcdcount_display > bcdcount_max) begin
                    bcdcount_max <= bcdcount_display;
                end
            end
            if (avg_counter != 0) begin
                if (avg_loop == (`AVERAGE_SIZE - 1)) begin
                    avg_counter_reg_avg <= (avg_counter_reg + avg_counter) >> `AVERAGE_BITS;
                    avg_counter_reg <= 0;
                    avg_loop <= 0;
                    avg_counter_start <= 1'b1;
                end else begin
                    avg_counter_reg <= avg_counter_reg + avg_counter;
                    avg_loop <= avg_loop + 1'b1;
                    avg_counter_start <= 1'b0;
                end
            end
            waiting <= 0;
        end
        if (avg_counter_ready) begin
            avg_counter_bcd_reg <= avg_counter_bcd_display;
        end
    end

    assign bcd_current = bcdcount_out;
    assign bcd_minimum = bcdcount_min;
    assign bcd_maximum = bcdcount_max;
    assign bcd_average = avg_counter_bcd_reg;

endmodule