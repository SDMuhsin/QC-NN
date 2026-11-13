// qb_col: one full column of qb_core (16 x 8) as a P&R slice (results/pnr_slice.md): 16 PEs (rows 0..15) of column
// 0, its 36 decoders + NNw (qbc_coldec), its 2 broadcast registers (one per 8-row group), its 32 fused lanes (PE rows
// 0..3 x 8 lanes) and 4 wide lanes, and its share of the parameter banks (8 fused + 8 wide channel records, plus the
// common mode bits, which the full core shares across columns).  Thin wrapper: qb_core with COLS = 1 instantiates
// exactly these modules (qbc_coldec, qbc_br, qbc_pe, qbf_lane, qbcw_lane, qbc_pbank_f #(8), qbc_pbank_w #(1)) with
// the same per-element connections as column c of the 16 x 8 core; qb_core itself is unchanged.  Port layout as
// qb_core #(ROWS 16, COLS 1): act[row] = 288 b per PE row, cd = the column's 36 codes, lane index L = 8 q + i.
module qb_col (
    input  logic clk, rst_n,
    input  logic [36*8-1:0] cd, input logic [9:0] ctl, input logic [16*36*8-1:0] act, input logic [8*17-1:0] t2,
    output logic [16*8-1:0] b2, output logic b2_vld,
    input  logic f_vld, f_src, f_sh, p_ld, input logic [8*81+4:0] pf, input logic [4*8*17-1:0] s_rd,
    output logic f_vld_o, output logic [4*8*17-1:0] f_y, output logic [4*8-1:0] f_b,
    input  logic w_vld, w_sh, w_ld, input logic [8*79+2:0] pw, input logic [4*19-1:0] w_r,
    output logic w_vld_o, output logic [4*19-1:0] w_y, output logic [4-1:0] w_b
);
    qb_core #(.ROWS(16), .COLS(1)) u_core (.*);
endmodule

// pnr_slice2.md variants (same ports; qb_core options CREG / WTP / FTP / PPOP):
//   qb_col_c     CREG                       (PE S0 code registers removed; latencies unchanged)
//   qb_col_cw    CREG + WTP                 (wide lane latency 5)
//   qb_col_cwf   CREG + WTP + FTP           (+ fused lane latency 4)
//   qb_col_cwfp  CREG + WTP + FTP + PPOP    (+ PE weighted group sum retimed into S2; latency unchanged)
`define QB_COL_V(NAME, CR_, WT_, FT_, PP_) \
module NAME ( \
    input  logic clk, rst_n, \
    input  logic [36*8-1:0] cd, input logic [9:0] ctl, input logic [16*36*8-1:0] act, input logic [8*17-1:0] t2, \
    output logic [16*8-1:0] b2, output logic b2_vld, \
    input  logic f_vld, f_src, f_sh, p_ld, input logic [8*81+4:0] pf, input logic [4*8*17-1:0] s_rd, \
    output logic f_vld_o, output logic [4*8*17-1:0] f_y, output logic [4*8-1:0] f_b, \
    input  logic w_vld, w_sh, w_ld, input logic [8*79+2:0] pw, input logic [4*19-1:0] w_r, \
    output logic w_vld_o, output logic [4*19-1:0] w_y, output logic [4-1:0] w_b \
); \
    qb_core #(.ROWS(16), .COLS(1), .CREG(CR_), .WTP(WT_), .FTP(FT_), .PPOP(PP_)) u_core (.*); \
endmodule
`QB_COL_V(qb_col_c, 1, 0, 0, 0)
`QB_COL_V(qb_col_cw, 1, 1, 0, 0)
`QB_COL_V(qb_col_cwf, 1, 1, 1, 0)
`QB_COL_V(qb_col_cwfp, 1, 1, 1, 1)
// pnr_slice3.md: qb_col_cwfp + one broadcast register per 2 PE rows (qb_core BRG 2; 8 BRs instead of 2)
module qb_col_cwfp_b2 (
    input  logic clk, rst_n,
    input  logic [36*8-1:0] cd, input logic [9:0] ctl, input logic [16*36*8-1:0] act, input logic [8*17-1:0] t2,
    output logic [16*8-1:0] b2, output logic b2_vld,
    input  logic f_vld, f_src, f_sh, p_ld, input logic [8*81+4:0] pf, input logic [4*8*17-1:0] s_rd,
    output logic f_vld_o, output logic [4*8*17-1:0] f_y, output logic [4*8-1:0] f_b,
    input  logic w_vld, w_sh, w_ld, input logic [8*79+2:0] pw, input logic [4*19-1:0] w_r,
    output logic w_vld_o, output logic [4*19-1:0] w_y, output logic [4-1:0] w_b
);
    qb_core #(.ROWS(16), .COLS(1), .CREG(1), .WTP(1), .FTP(1), .PPOP(1), .BRG(2)) u_core (.*);
endmodule
