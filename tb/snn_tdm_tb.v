// Testbench for snn_top_tdm
// Runs the same 6 test cases as snn_parallel_tb.v.
// result_valid takes NUM_CLASSES * WINDOW_LEN cycles (256 cycles for N=4).

`timescale 1ns/1ps

module snn_tdm_tb;

    localparam NUM_INPUTS = 25;
    localparam NUM_CLASSES = 4;
    localparam CLS_WIDTH = 2;
    localparam WINDOW_LEN = 64;

    localparam TOTAL_CYCLES = NUM_CLASSES * WINDOW_LEN;
    localparam TIMEOUT = TOTAL_CYCLES + 32;

    localparam [24:0] DIGIT_0 = 25'b01110_10001_10001_10001_01110;
    localparam [24:0] DIGIT_1 = 25'b00100_01100_00100_00100_01110;
    localparam [24:0] DIGIT_2 = 25'b01110_00001_01110_10000_11111;
    localparam [24:0] DIGIT_3 = 25'b01110_00001_01110_00001_01110;
    localparam [24:0] ALL_ONES = {25{1'b1}};
    localparam [24:0] NOISY_2 = DIGIT_2 ^ 25'b10000_00000_00000_00000_00001;

    reg clk, rst;
    reg [NUM_INPUTS-1:0] pattern;
    reg classify_start;
    wire [CLS_WIDTH-1:0] predicted_class;
    wire result_valid;
    wire [NUM_CLASSES-1:0] spike_bus;
    wire [NUM_CLASSES*8-1:0] counts_dbg;

    snn_top_tdm #(
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

    task print_pattern;
        input [NUM_INPUTS-1:0] pat;
        integer r, c;
        begin
            for (r = 4; r >= 0; r = r - 1) begin
                $write("    ");
                for (c = 4; c >= 0; c = c - 1)
                    $write("%s", pat[r*5+c] ? "#" : ".");
                $write("\n");
            end
        end
    endtask

    integer pass_count, fail_count, timeout_cnt;

    task run_test;
        input [NUM_INPUTS-1:0] pat;
        input [CLS_WIDTH-1:0] expected;
        input [8*40-1:0] label;
        input do_check;
        begin
            rst = 1'b1;
            pattern = 0;
            classify_start = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;

            pattern = pat;
            repeat (2) @(negedge clk);
            classify_start = 1'b1;
            @(negedge clk);
            classify_start = 1'b0;

            timeout_cnt = 0;
            while (!result_valid && timeout_cnt < TIMEOUT) begin
                @(posedge clk);
                #1;
                timeout_cnt = timeout_cnt + 1;
            end

            $write("%0s\n", label);
            print_pattern(pat);
            if (timeout_cnt >= TIMEOUT) begin
                $display("  -> TIMEOUT: result_valid never asserted");
                fail_count = fail_count + 1;
            end else begin
                $display("  -> class=%0d (after %0d cycles)", predicted_class, timeout_cnt);
                $display("     counts: n0=%0d n1=%0d n2=%0d n3=%0d",
                    counts_dbg[7:0], counts_dbg[15:8],
                    counts_dbg[23:16], counts_dbg[31:24]);
                if (!do_check) begin
                    $display("  -> INFO only\n");
                end else if (predicted_class === expected) begin
                    $display("  -> PASS (expected %0d)\n", expected);
                    pass_count = pass_count + 1;
                end else begin
                    $display("  -> FAIL (expected %0d)\n", expected);
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("sim/snn_tdm_tb.vcd");
        $dumpvars(0, snn_tdm_tb);

        pass_count = 0;
        fail_count = 0;

        $display("");
        $display("4-neuron TDM pattern detector");
        $display("WINDOW=%0d, %0d cycles per classification\n", WINDOW_LEN, TOTAL_CYCLES);

        run_test(DIGIT_0, 2'd0, "Test 1: DIGIT 0", 1'b1);
        run_test(DIGIT_1, 2'd1, "Test 2: DIGIT 1", 1'b1);
        run_test(DIGIT_2, 2'd2, "Test 3: DIGIT 2", 1'b1);
        run_test(DIGIT_3, 2'd3, "Test 4: DIGIT 3", 1'b1);
        run_test(NOISY_2, 2'd2, "Test 5: NOISY DIGIT 2", 1'b1);
        run_test(ALL_ONES, 2'd0, "Test 6: ALL ONES (reject)", 1'b0);

        if (counts_dbg === {NUM_CLASSES*8{1'b0}}) begin
            $display("  -> PASS: all neurons silent, pattern rejected\n");
            pass_count = pass_count + 1;
        end else begin
            $display("  -> FAIL: expected zero spikes\n");
            fail_count = fail_count + 1;
        end

        $display("------------------------------------");
        $display("RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else $display("SOME TESTS FAILED");
        $display("------------------------------------");
        $finish;
    end

endmodule
