// Weight MAC unit for SNN
// Multiplies binary input spikes by signed weights and sums them up.
// Output clamps at 0 on the negative side and saturates on positive overflow.

module weight_mac #(
    parameter NUM_INPUTS = 25,
    parameter W_WIDTH = 8,
    parameter OUT_WIDTH = 16
)(
    input wire [NUM_INPUTS-1:0] spikes_in,
    input wire [NUM_INPUTS*W_WIDTH-1:0] weights_flat,
    output wire [OUT_WIDTH-1:0] current_out
);

    // Make sure accumulator has enough headroom for worst-case sum and overflow check
    localparam ACC_RAW = W_WIDTH + $clog2(NUM_INPUTS) + 1;
    localparam ACC_WIDTH = (ACC_RAW > OUT_WIDTH + 1) ? ACC_RAW : OUT_WIDTH + 1;

    reg signed [ACC_WIDTH-1:0] acc;
    integer i;

    always @(*) begin
        acc = 0;
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            if (spikes_in[i]) begin
                acc = acc + $signed(weights_flat[i*W_WIDTH +: W_WIDTH]);
            end
        end
    end

    // Clamping logic
    wire is_negative = acc[ACC_WIDTH-1];
    wire signed [ACC_WIDTH-1:0] shifted = acc >>> OUT_WIDTH;
    wire is_overflow = (!is_negative) && (shifted != 0);

    assign current_out = is_negative ? {OUT_WIDTH{1'b0}} : is_overflow ? {OUT_WIDTH{1'b1}} : acc[OUT_WIDTH-1:0];

endmodule
