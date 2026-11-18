// Spike counter and argmax decision block
// Counts spikes per neuron over an observation window, then outputs the winner.

module spike_counter #(
    parameter NUM_CLASSES = 4,
    parameter COUNT_WIDTH = 8,
    parameter WINDOW_LEN = 64
)(
    input wire clk,
    input wire rst,
    input wire window_start,
    input wire [NUM_CLASSES-1:0] spikes_in,
    output reg [CLS_WIDTH-1:0] predicted_class,
    output reg valid,
    output wire [NUM_CLASSES*COUNT_WIDTH-1:0] counts_flat
);

    localparam CLS_WIDTH = (NUM_CLASSES > 1) ? $clog2(NUM_CLASSES) : 1;
    localparam CYC_WIDTH = (WINDOW_LEN > 1) ? $clog2(WINDOW_LEN) : 1;

    reg counting;
    reg [CYC_WIDTH-1:0] cycle_cnt;
    reg [COUNT_WIDTH-1:0] counts [0:NUM_CLASSES-1];
    integer i, j;

    // Window timer and per-neuron spike counters
    always @(posedge clk) begin
        if (rst) begin
            counting <= 1'b0;
            cycle_cnt <= 0;
            valid <= 1'b0;
            for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                counts[i] <= 0;
            end
        end else if (window_start) begin
            counting <= 1'b1;
            cycle_cnt <= 0;
            valid <= 1'b0;
            for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                counts[i] <= 0;
            end
        end else if (counting) begin
            for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                if (spikes_in[i]) begin
                    counts[i] <= counts[i] + 1'b1;
                end
            end

            if (cycle_cnt == WINDOW_LEN - 1) begin
                counting <= 1'b0;
                valid <= 1'b1;
            end
            cycle_cnt <= cycle_cnt + 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end

    // Combinational argmax - lowest index wins ties
    reg [COUNT_WIDTH-1:0] max_count;
    always @(*) begin
        max_count = 0;
        predicted_class = 0;
        for (j = 0; j < NUM_CLASSES; j = j + 1) begin
            if (counts[j] > max_count) begin
                max_count = counts[j];
                predicted_class = j[CLS_WIDTH-1:0];
            end
        end
    end

    // Flatten array for debug/top-level visibility
    genvar g;
    generate
        for (g = 0; g < NUM_CLASSES; g = g + 1) begin : pack
            assign counts_flat[g*COUNT_WIDTH +: COUNT_WIDTH] = counts[g];
        end
    endgenerate

endmodule
