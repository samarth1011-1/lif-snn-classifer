// Parallel SNN top module for pattern detection
// Instantiates one weight_mac and lif_neuron per class.

module snn_top_parallel #(
    parameter NUM_INPUTS = 25,
    parameter NUM_CLASSES = 4,
    parameter W_WIDTH = 8,
    parameter V_WIDTH = 16,
    parameter K = 5,
    parameter [15:0] V_TH = 16'd384,
    parameter WINDOW_LEN = 64,
    parameter signed [W_WIDTH-1:0] W_ON = 8'sd16,
    parameter signed [W_WIDTH-1:0] W_OFF = -8'sd32
)(
    input wire clk,
    input wire rst,
    input wire [NUM_INPUTS-1:0] pattern_in,
    input wire classify_start,
    output wire [CLS_WIDTH-1:0] predicted_class,
    output wire result_valid,
    output wire [NUM_CLASSES-1:0] spike_bus,
    output wire [NUM_CLASSES*8-1:0] counts_dbg
);

    localparam CLS_WIDTH = (NUM_CLASSES > 1) ? $clog2(NUM_CLASSES) : 1;

    // 5x5 templates for digits 0 to 3
    function [NUM_INPUTS-1:0] class_template;
        input integer c;
        begin
            case (c)
                0: class_template = 25'b01110_10001_10001_10001_01110; // "0"
                1: class_template = 25'b00100_01100_00100_00100_01110; // "1"
                2: class_template = 25'b01110_00001_01110_10000_11111; // "2"
                3: class_template = 25'b01110_00001_01110_00001_01110; // "3"
                default: class_template = {NUM_INPUTS{1'b0}};
            endcase
        end
    endfunction

    wire [NUM_CLASSES-1:0] spikes;

    genvar c, k;
    generate
        for (c = 0; c < NUM_CLASSES; c = c + 1) begin : neuron
            wire [NUM_INPUTS*W_WIDTH-1:0] weights_flat;

            // Generate weights from template
            for (k = 0; k < NUM_INPUTS; k = k + 1) begin : wgen
                wire [NUM_INPUTS-1:0] tmpl = class_template(c);
                assign weights_flat[k*W_WIDTH +: W_WIDTH] = tmpl[k] ? W_ON : W_OFF;
            end

            wire [V_WIDTH-1:0] current;

            weight_mac #(
                .NUM_INPUTS(NUM_INPUTS),
                .W_WIDTH(W_WIDTH),
                .OUT_WIDTH(V_WIDTH)
            ) u_mac (
                .spikes_in(pattern_in),
                .weights_flat(weights_flat),
                .current_out(current)
            );

            lif_neuron #(
                .K(K),
                .V_TH(V_TH)
            ) u_lif (
                .clk(clk),
                .rst(rst),
                .i_input(current),
                .spike(spikes[c]),
                .v_mem_out()
            );
        end
    endgenerate

    assign spike_bus = spikes;

    // Decision logic
    spike_counter #(
        .NUM_CLASSES(NUM_CLASSES),
        .COUNT_WIDTH(8),
        .WINDOW_LEN(WINDOW_LEN)
    ) u_decision (
        .clk(clk),
        .rst(rst),
        .window_start(classify_start),
        .spikes_in(spikes),
        .predicted_class(predicted_class),
        .valid(result_valid),
        .counts_flat(counts_dbg)
    );

endmodule
