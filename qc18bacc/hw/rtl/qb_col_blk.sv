// qb_col_blk (results/r5a.md): hard-block column of the 16 x 8 core for the abutted 8-column array of qb_chip.
// Logic = qb_col_cwfp_b2 = one column of qb_core #(CREG 1, WTP 1, FTP 1, PPOP 1, BRG 2), the configuration qb_top
// builds (qb_top.sv u_core).  qb_core #(COLS 8) is 8 such columns: per column the decoders, 8 BRs, 16 PEs, 32 fused +
// 4 wide lanes and the column's parameter records; the PPU control registers / common mode bits are duplicated per
// column (same values).  Added: act_o = act, a buffered feedthrough of the 16 x 288 activation row bits, so the act
// rows enter column 0 on the west edge and cross the array column by column (east edge pins at the same y).
module qb_col_blk (
    input  logic clk, rst_n,
    input  logic [36*8-1:0] cd, input logic [9:0] ctl, input logic [16*36*8-1:0] act, input logic [8*17-1:0] t2,
    output logic [16*36*8-1:0] act_o,
    output logic [16*8-1:0] b2, output logic b2_vld,
    input  logic f_vld, f_src, f_sh, p_ld, input logic [8*81+4:0] pf, input logic [4*8*17-1:0] s_rd,
    output logic f_vld_o, output logic [4*8*17-1:0] f_y, output logic [4*8-1:0] f_b,
    input  logic w_vld, w_sh, w_ld, input logic [8*79+2:0] pw, input logic [4*19-1:0] w_r,
    output logic w_vld_o, output logic [4*19-1:0] w_y, output logic [4-1:0] w_b
);
    assign act_o = act;
    qb_core #(.ROWS(16), .COLS(1), .CREG(1), .WTP(1), .FTP(1), .PPOP(1), .BRG(2)) u_core (
        .clk, .rst_n, .cd, .ctl, .act, .t2, .b2, .b2_vld, .f_vld, .f_src, .f_sh, .p_ld, .pf, .s_rd, .f_vld_o, .f_y,
        .f_b, .w_vld, .w_sh, .w_ld, .pw, .w_r, .w_vld_o, .w_y, .w_b);
endmodule
