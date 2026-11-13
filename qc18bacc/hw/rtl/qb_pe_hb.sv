// qb_pe_hb: hardened-PE wrapper (results/pnr_pe.md): one qbc_pe exactly as qb_core instantiates it with
// CREG = PPOP = 1 (KB 36, ACC_W 20, CR 1, PP 1), same ports, no logic.  Synthesised and routed as a block; the
// column top qb_col_cwfp_h (DC hook impl/hard/col_hb.tcl) links its 16 PEs to this design.
module qb_pe_hb (
    input  logic              clk, rst_n,
    input  logic [36*8-1:0]   a,
    input  logic [36*10-1:0]  c,
    input  logic signed [9:0] nnw,
    input  logic [9:0]        ctl,
    input  logic [8*17-1:0]   t2,
    input  logic              fsh, wsh,
    input  logic [8*20-1:0]   up,
    input  logic [19:0]       sh_in,
    output logic [8*20-1:0]   shd,
    output logic [19:0]       sh_out,
    output logic [7:0]        b2
);
    qbc_pe #(36, 20, 1, 1) u_pe (.*);
endmodule
