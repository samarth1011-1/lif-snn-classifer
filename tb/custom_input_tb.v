// Testbench to test any custom 5x5 pattern against stored templates (0-3)

`timescale 1ns/1ps

module custom_input_tb;

    // Put your 5x5 test pattern here (1 = ON, 0 = OFF)
    localparam [24:0] CUSTOM = {
        5'b10011, // row 4 (top)
        5'b01010, // row 3
        5'b10100, // row 2
        5'b01010, // row 1
        5'b10010  // row 0 (bottom)
    };

    localparam NUM_INPUTS = 25;
    localparam NUM_CLASSES = 4;
    localparam CLS_WIDTH = 2;
    localparam WINDOW_LEN = 64;

    // Reference templates
    localparam [24:0] DIGIT_0 = 25'b01110_10001_10001_10001_01110;
    localparam [24:0] DIGIT_1 = 25'b00100_01100_00100_00100_01110;
    localparam [24:0] DIGIT_2 = 25'b01110_00001_01110_10000_11111;
    localparam [24:0] DIGIT_3 = 25'b01110_00001_01110_00001_01110;

    reg clk, rst;
    reg [NUM_INPUTS-1:0] pattern;
    reg classify_start;
    wire [CLS_WIDTH-1:0] predicted_class;
    wire result_valid;
    wire [NUM_CLASSES-1:0] spike_bus;
    wire [NUM_CLASSES*8-1:0] counts_dbg;

    snn_top_parallel #(
        .NUM_INPUTS(NUM_INPUTS),
        .NUM_CLASSES(NUM_CLASSES),
        .WINDOW_LEN(WINDOW_LEN)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .pattern_in(pattern),
        .classify_start(classify_start),
        .predicted_class(predicted_class),
        .result_valid(result_valid),
        .spike_bus(spike_bus),
        .counts_dbg(counts_dbg)
    );

    initial clk = 0;
    always #10 clk = ~clk;

    task print_row;
        input [4:0] row;
        integer c;
        begin
            for (c = 4; c >= 0; c = c - 1)
                $write("%s", row[c] ? "#" : ".");
        end
    endtask

    function integer match_count;
        input [24:0] a, b;
        integer m, bit_idx;
        begin
            m = 0;
            for (bit_idx = 0; bit_idx < 25; bit_idx = bit_idx + 1)
                if (a[bit_idx] == b[bit_idx]) m = m + 1;
            match_count = m;
        end
    endfunction

    wire [7:0] cnt0 = counts_dbg[7:0];
    wire [7:0] cnt1 = counts_dbg[15:8];
    wire [7:0] cnt2 = counts_dbg[23:16];
    wire [7:0] cnt3 = counts_dbg[31:24];

    integer timeout_cnt;

    initial begin
        $dumpfile("sim/custom_input.vcd");
        $dumpvars(0, custom_input_tb);

        // Reset
        rst = 1;
        pattern = 0;
        classify_start = 0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Apply input pattern and pulse start
        pattern = CUSTOM;
        repeat (2) @(negedge clk);
        classify_start = 1;
        @(negedge clk);
        classify_start = 0;

        timeout_cnt = 0;
        while (!result_valid && timeout_cnt < 300) begin
            @(posedge clk);
            #1;
            timeout_cnt = timeout_cnt + 1;
        end

        // Display results
        $display("");
        $display("----------------------------------------------------------------");
        $display("  YOUR INPUT        Digit 0    Digit 1    Digit 2    Digit 3");
        $display("----------------------------------------------------------------");

        begin : print_block
            integer r;
            for (r = 4; r >= 0; r = r - 1) begin
                $write("    ");
                print_row(CUSTOM[r*5 +: 5]);
                $write("           ");
                print_row(DIGIT_0[r*5 +: 5]);
                $write("      ");
                print_row(DIGIT_1[r*5 +: 5]);
                $write("      ");
                print_row(DIGIT_2[r*5 +: 5]);
                $write("      ");
                print_row(DIGIT_3[r*5 +: 5]);
                $write("\n");
            end
        end

        $display("");
        $display("----------------------------------------------------------------");
        $display("  NEURON RESPONSES (%0d-cycle window)", WINDOW_LEN);
        $display("----------------------------------------------------------------");
        $display("   Neuron 0 (digit 0):  %3d spikes   pixel match: %0d/25", cnt0, match_count(CUSTOM, DIGIT_0));
        $display("   Neuron 1 (digit 1):  %3d spikes   pixel match: %0d/25", cnt1, match_count(CUSTOM, DIGIT_1));
        $display("   Neuron 2 (digit 2):  %3d spikes   pixel match: %0d/25", cnt2, match_count(CUSTOM, DIGIT_2));
        $display("   Neuron 3 (digit 3):  %3d spikes   pixel match: %0d/25", cnt3, match_count(CUSTOM, DIGIT_3));
        $display("");

        $display("----------------------------------------------------------------");
        $display("  SPIKE HISTOGRAM");
        $display("----------------------------------------------------------------");
        begin : bar_chart
            integer n, b;
            reg [7:0] cnts [0:3];
            cnts[0] = cnt0;
            cnts[1] = cnt1;
            cnts[2] = cnt2;
            cnts[3] = cnt3;

            for (n = 0; n < 4; n = n + 1) begin
                $write("   Neuron %0d: ", n);
                for (b = 0; b < cnts[n]; b = b + 1)
                    $write("|");
                if (cnts[n] == 0)
                    $write("(silent)");
                $write(" [%0d]\n", cnts[n]);
            end
        end

        $display("");
        $display("----------------------------------------------------------------");
        if (cnt0 == 0 && cnt1 == 0 && cnt2 == 0 && cnt3 == 0) begin
            $display("  RESULT:  NO MATCH (pattern rejected, all neurons silent)");
        end else begin
            $display("  RESULT:  Predicted digit = %0d", predicted_class);
        end
        $display("----------------------------------------------------------------");
        $display("");

        $finish;
    end

endmodule
