// Time-multiplexed SNN pattern detector
// Shares one weight_mac and one combinational LIF datapath across all N classes.
// Cycles through neuron_id 0..N-1 round-robin (1 neuron per clock), so each
// classification takes NUM_CLASSES * WINDOW_LEN cycles.

module snn_top_tdm #(
    parameter NUM_INPUTS = 25,
    parameter NUM_CLASSES = 4,
    parameter W_WIDTH = 8,
    parameter V_WIDTH = 16,
    parameter K = 5,
    parameter [15:0] V_TH = 16'd384,
    parameter WINDOW_LEN = 64,
    parameter signed [W_WIDTH-1:0] W_ON = 8'sd16, // +16
    parameter signed [W_WIDTH-1:0] W_OFF = -8'sd32 // -32
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

    localparam CLS_WIDTH = (NUM_CLASSES > 1)? $clog2(NUM_CLASSES) : 1;
    localparam CYC_WIDTH = (WINDOW_LEN > 1)? $clog2(WINDOW_LEN) : 1;
    localparam NID_WIDTH = (NUM_CLASSES > 1)? $clog2(NUM_CLASSES) : 1;

    // Same 5x5 templates
    function [NUM_INPUTS-1:0] class_template;
        input integer c;
        begin
            case (c)
                0: class_template = 25'b01110_10001_10001_10001_01110;
                1: class_template = 25'b00100_01100_00100_00100_01110;
                2: class_template = 25'b01110_00001_01110_10000_11111;
                3: class_template = 25'b01110_00001_01110_00001_01110;
                default:class_template = {NUM_INPUTS{1'b0}};
            endcase
        end
    endfunction

    // Weight ROM from templates
    reg signed [W_WIDTH-1:0] weight_rom [0:NUM_CLASSES*NUM_INPUTS-1];
    integer ci, ki;
    reg [NUM_INPUTS-1:0] tmpl;
    initial begin
        for (ci = 0; ci < NUM_CLASSES; ci = ci + 1) begin
            tmpl = class_template(ci);
            for (ki = 0; ki < NUM_INPUTS; ki = ki + 1)
                weight_rom[ci * NUM_INPUTS + ki] = tmpl[ki] ? W_ON : W_OFF;
        end
    end

    // Neuron state register
    reg [V_WIDTH-1:0] vmem_state [0:NUM_CLASSES-1];
    reg [7:0] spike_counts [0:NUM_CLASSES-1];
    reg [NUM_CLASSES-1:0] spike_out_reg;

    reg [NID_WIDTH-1:0] neuron_id;
    reg [CYC_WIDTH-1:0] window_cnt;
    reg active;
    reg valid_r;

    // Choose the weight row for whichever neuron is active this cycle
    wire [NUM_INPUTS*W_WIDTH-1:0] weights_flat;
    genvar k;
    generate
        for (k = 0; k < NUM_INPUTS; k = k + 1) begin : wsel
            assign weights_flat[k*W_WIDTH +: W_WIDTH] = weight_rom[neuron_id * NUM_INPUTS + k];
        end
    endgenerate

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

    // Combinational LIF datapath
    // inlined so yosys doesnt choke on mem port (coz it did once)
    wire [V_WIDTH-1:0]v_mem_curr = vmem_state[neuron_id];
    wire [V_WIDTH-1:0] leak_amt = (v_mem_curr + ((16'd1 << K) - 1)) >> K;
    wire [V_WIDTH-1:0]decayed = v_mem_curr - leak_amt;
    wire [V_WIDTH:0]sum_wire = decayed + current;
    wire [V_WIDTH-1:0] integrated = sum_wire[V_WIDTH] ? {V_WIDTH{1'b1}} : sum_wire[V_WIDTH-1:0];

    wire spike_comb= (integrated >= V_TH);
    wire [V_WIDTH-1:0] v_mem_next = spike_comb ? {V_WIDTH{1'b0}} : integrated;

    // Round-robin FSM + state writeback
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            active <= 1'b0;
            valid_r <= 1'b0;
            neuron_id <= 0;
            window_cnt <= 0;
            spike_out_reg <= 0;
            for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                vmem_state[i] <= 0;
                spike_counts[i] <= 0;
            end
        end else if (classify_start) begin
            active <= 1'b1;
            valid_r <= 1'b0;
            neuron_id <= 0;
            window_cnt <= 0;
            spike_out_reg <= 0;
            for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                vmem_state[i] <= 0;
                spike_counts[i] <= 0;
            end
        end else if (active) begin
            vmem_state[neuron_id] <= v_mem_next;

            if (spike_comb) begin
                spike_counts[neuron_id] <= spike_counts[neuron_id] + 1;
                spike_out_reg[neuron_id] <= 1'b1;
            end else begin
                spike_out_reg[neuron_id] <= 1'b0;
            end

            if (neuron_id == NUM_CLASSES - 1) begin
                neuron_id <= 0;
                if (window_cnt == WINDOW_LEN - 1) begin
                    active <= 1'b0;
                    valid_r <= 1'b1;
                end else begin
                    window_cnt <= window_cnt + 1;
                end
            end else begin
                neuron_id <= neuron_id + 1;
            end
        end else begin
            valid_r <= 1'b0;
        end
    end

    // Combinational argmax (lowest index wins on a tie situation)
    reg [CLS_WIDTH-1:0] predicted_r;
    reg [7:0] max_count;
    integer j;
    always @(*) begin
        max_count = 0;
        predicted_r = 0;
        for (j = 0; j < NUM_CLASSES; j = j + 1) begin
            if (spike_counts[j] > max_count) begin
                max_count = spike_counts[j];
                predicted_r = j[CLS_WIDTH-1:0];
            end
        end
    end

    assign predicted_class = predicted_r;
    assign result_valid = valid_r;
    assign spike_bus = spike_out_reg;

    genvar g;
    generate
        for (g = 0; g < NUM_CLASSES; g = g + 1) begin : pack
            assign counts_dbg[g*8 +: 8] = spike_counts[g];
        end
    endgenerate

endmodule
