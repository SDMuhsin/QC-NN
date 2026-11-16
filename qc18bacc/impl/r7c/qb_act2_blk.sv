// R7c (results/r7c.md): hard-block wrapper of the act supply for the west strip of qb_chip.  = qb_top's u_act
// (qb_act2 #(ACT_PIPE AP)) + its act distribution g_dist (DIST qbt_dreg stages of 4 608 b): ACT_PIPE = AP + DIST
// (QB_ACT2_BLK_PIPE, default 2 = the chip's AP 1 + DIST 1).  The block's act outputs then come straight from the last
// pipe flop, so its east edge can abut column 0's act pins (no top-level register in between).  Act timing is
// identical (act at i + 3 + AP + DIST); only the debug a_* descriptor outputs move DIST cycles later (unused in
// qb_chip).  Chip integration: qb_top #(.AP(2), .DIST(0)) keeps D = 2 + AP + DIST = 4.  No existing RTL changed.
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
    qb_act2 #(.ACT_PIPE(`QB_ACT2_BLK_PIPE)) u_act (.*);
endmodule
