module lif_neuron_comb #(
    parameter K = 5,
    parameter [15:0] V_TH = 16'd384
)(
    input wire [15:0] v_mem_in,
    input wire [15:0] i_input,
    output wire [15:0] v_mem_next,
    output wire spike
);

    // Same operations as lif_neuron.v but completely combinational 
    wire [15:0] leak_amt = (v_mem_in + ((16'd1 << K) - 1)) >> K;
    wire [15:0] decayed  = v_mem_in - leak_amt;
    wire [16:0] sum_wire = decayed + i_input;
    wire [15:0] integrated = sum_wire[16] ? 16'hFFFF : sum_wire[15:0];

    assign spike= (integrated >= V_TH);
    assign v_mem_next = spike ? 16'd0 : integrated;

endmodule
