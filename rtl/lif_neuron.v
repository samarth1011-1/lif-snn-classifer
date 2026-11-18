module lif_neuron #(
        parameter K = 5,
        parameter [15:0] V_TH = 16'd256
)(
        input clk,rst,
        input [15:0] i_input,
        output reg spike,
        output [15:0] v_mem_out
);

reg [15:0] v_mem_reg;
wire [15:0] leak_amt,decayed,v_mem_next;
wire [16:0] sum_wire;
wire spike_cond;

// Round-up leak: ceiling division by 2^K
// leak_amt = (v_mem_reg + (2^K - 1)) >> K
// This guarantees any nonzero v_mem_reg leaks at least 1, so Vmem always decays to 0.
assign leak_amt = (v_mem_reg + ((16'd1 << K) - 1)) >> K;  // { v_mem_reg + (2^K - 1) / 2^K }
assign decayed = v_mem_reg - leak_amt;
assign sum_wire = decayed + i_input;
assign v_mem_next = (sum_wire[16])?16'hFFFF:sum_wire[15:0];
assign spike_cond = (v_mem_next >= V_TH);

// Debug output: expose membrane voltage
assign v_mem_out = v_mem_reg;

always@(posedge clk) begin
        if(rst) begin
            spike<=0;
            v_mem_reg<=0;
        end
        else begin
            if(spike_cond) begin
                    v_mem_reg<=0;
                    spike<=1;
            end
            else begin
                    v_mem_reg<=v_mem_next;
                    spike<=0;
            end
        end
end
endmodule
