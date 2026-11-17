// R13 (results/r13.md): impl/r7c/qb_act2_blk.sv (unchanged default) + opt-in QB13_BLK_CHIP: exactly the chip's cone,
// qb_top's u_act = qb_act2 #(ACT_PIPE 1) followed by one 4 608-b act register (qb_top g_dist: qbt_dreg #(4608), here the
// identical qb13_dreg so qb_top.sv need not be read).  R7c's ACT_PIPE 2 made done / a_eot / a_ctx (sequencer start,
// image-buffer free) one cycle later than in the chip (R11 finding); with QB13_BLK_CHIP every output equals qb_top's
// u_act outputs and act equals actd[1].  act still leaves the block from a flop.
`ifndef QB_ACT2_BLK_PIPE
`define QB_ACT2_BLK_PIPE 2
`endif
module qb_act2_blk (
    input  logic clk, rst_n,
    input  logic [1:0] start,
    input  logic [1:0][3:0] c_cfg,
    input  logic [1:0][4:0] c_nchunk,
    input  logic [1:0][3:0] c_nct,
    input  logic [1:0][6:0] c_ntile,
    input  logic [1:0] c_int8, c_stem,
    input  logic [1:0][8:0] c_base,
    output logic [1:0] busy, done,
    input  logic [1:0] tgo, l_ok,
    input  logic [15:0] l_seq0, l_seq1,
    output logic [9:0] l_pos0, l_pos1,
    input  logic f_clr, f_we, f_nz,
    input  logic [1:0] f_bank,
    input  logic [6:0] f_idx,
    output logic m_ren,
    output logic [8:0] m_ra,
    output logic m_ctx,
    input  logic [511:0] m_q,
    output logic s_ren,
    output logic [7:0] s_ra,
    output logic s_ctx,
    input  logic [2047:0] s_q,
    output logic d_vld, d_first, d_eot, d_neg, d_stem, d_g3n, d_ctx,
    output logic [2:0] d_plane,
    output logic [3:0] d_chunk,
    output logic [2:0] d_ct,
    output logic [5:0] d_tile,
    output logic [4607:0] act,
    output logic a_vld, a_first, a_eot, a_neg, a_stem, a_g3n, a_ctx,
    output logic [2:0] a_plane,
    output logic [3:0] a_chunk,
    output logic [2:0] a_ct,
    output logic [5:0] a_tile,
    output logic err);
`ifdef QB13_BLK_CHIP
    logic [4607:0] a_act;
    qb_act2 #(.ACT_PIPE(1)) u_act (.clk, .rst_n, .start, .c_cfg, .c_nchunk, .c_nct, .c_ntile, .c_int8, .c_stem, .c_base,
        .busy, .done, .tgo, .l_ok, .l_seq0, .l_seq1, .l_pos0, .l_pos1, .f_clr, .f_we, .f_nz, .f_bank, .f_idx, .m_ren,
        .m_ra, .m_ctx, .m_q, .s_ren, .s_ra, .s_ctx, .s_q, .d_vld, .d_first, .d_eot, .d_neg, .d_stem, .d_g3n, .d_ctx,
        .d_plane, .d_chunk, .d_ct, .d_tile, .act(a_act), .a_vld, .a_first, .a_eot, .a_neg, .a_stem, .a_g3n, .a_ctx,
        .a_plane, .a_chunk, .a_ct, .a_tile, .err);
    qb13_dreg #(4608) u_dist (.clk, .d(a_act), .q(act));
`else
    qb_act2 #(.ACT_PIPE(`QB_ACT2_BLK_PIPE)) u_act (.*);
`endif
endmodule

`ifdef QB13_BLK_CHIP
module qb13_dreg #(parameter int W = 1) (input logic clk, input logic [W-1:0] d, output logic [W-1:0] q);   // = qbt_dreg
    always_ff @(posedge clk) q <= d;
endmodule
`endif
