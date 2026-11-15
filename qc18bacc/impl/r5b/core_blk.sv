// R5b (results/r5b.md): qb_core of the chip as 8 abutted column hard blocks.  Same parameters / ports as qb_core
// (parameters ignored: the blocks are the R5d build, CREG 2 / WSHP 1, port-timing-equivalent to qb_top's CREG 1);
// body = hw/tb/qb_colarr.sv (8 x qb_col_blk, act chained through the feedthroughs).  qb_col_blk has no RTL in the
// R5b file list: DC links it to the block ETM (.db), P&R to the block LEF + ETM.
module qb_core #(parameter int ROWS = 16, COLS = 8, KB = 36, MWF = 28, CREG = 0, WTP = 0, FTP = 0, PPOP = 0, BRG = 8,
                 WSHP = 0) (
    input  logic                         clk, rst_n,
    input  logic [COLS*KB*8-1:0]         cd,
    input  logic [9:0]                   ctl,
    input  logic [ROWS*KB*8-1:0]         act,
    input  logic [COLS*8*17-1:0]         t2,
    output logic [ROWS*COLS*8-1:0]       b2,
    output logic                         b2_vld,
    input  logic                         f_vld, f_src, f_sh, p_ld,
    input  logic [COLS*8*(37+MWF+16)+4:0] pf,
    input  logic [4*COLS*8*17-1:0]       s_rd,
    output logic                         f_vld_o,
    output logic [4*COLS*8*17-1:0]       f_y,
    output logic [4*COLS*8-1:0]          f_b,
    input  logic                         w_vld, w_sh, w_ld,
    input  logic [COLS*8*79+2:0]         pw,
    input  logic [4*COLS*19-1:0]         w_r,
    output logic                         w_vld_o,
    output logic [4*COLS*19-1:0]         w_y,
    output logic [4*COLS-1:0]            w_b
);
    qb_colarr u_arr (.clk, .rst_n, .cd, .ctl, .act, .t2, .b2, .b2_vld, .f_vld, .f_src, .f_sh, .p_ld, .pf, .s_rd,
        .f_vld_o, .f_y, .f_b, .w_vld, .w_sh, .w_ld, .pw, .w_r, .w_vld_o, .w_y, .w_b);
endmodule
