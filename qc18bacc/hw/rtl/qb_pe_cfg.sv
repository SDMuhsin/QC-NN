// Synthesis tops of qb_pe, one per configuration (KB, ACC_W) (fixed module names for the DC / PT flow).
`define QB_PE_CFG(NAME, KB_, AW_) \
module NAME (input logic clk, rst_n, input logic [KB_*8-1:0] a, input logic [KB_*10-1:0] c, \
             input logic [2:0] plane, input logic neg, valid, first, capture, shift, \
             input logic [AW_-1:0] sh_in, output logic [AW_-1:0] sh_out); \
    qb_pe #(.KB(KB_), .ACC_W(AW_)) u_pe (.*); \
endmodule
`QB_PE_CFG(qb_pe_k8_a20,  8,  20)
`QB_PE_CFG(qb_pe_k16_a20, 16, 20)
`QB_PE_CFG(qb_pe_k32_a20, 32, 20)
`QB_PE_CFG(qb_pe_k16_a14, 16, 14)
