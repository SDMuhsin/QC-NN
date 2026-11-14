// qb_colarr (results/r5a.md): the 16 x 8 core as 8 abutted qb_col_blk hard blocks, with the ports of qb_core
// #(ROWS 16, COLS 8): act enters column 0 and crosses the array through the act -> act_o feedthroughs; per-column
// slices of cd / t2 / pf / pw / s_rd / w_r / b2 / lane outputs exactly as qb_core's per-column indexing (lane
// L = 64 q + 8 c + i fused, 8 q + c wide; parameter record 8 c + k, common bits shared); valids from column 0.
// Used by tb_qb_core.sv with -DQBC_COLARR, on the RTL wrapper or on the block netlist (gate-level check).
module qb_colarr (
    input  logic clk, rst_n,
    input  logic [8*36*8-1:0] cd, input logic [9:0] ctl, input logic [16*36*8-1:0] act, input logic [8*8*17-1:0] t2,
    output logic [16*8*8-1:0] b2, output logic b2_vld,
    input  logic f_vld, f_src, f_sh, p_ld, input logic [8*8*81+4:0] pf, input logic [4*8*8*17-1:0] s_rd,
    output logic f_vld_o, output logic [4*8*8*17-1:0] f_y, output logic [4*8*8-1:0] f_b,
    input  logic w_vld, w_sh, w_ld, input logic [8*8*79+2:0] pw, input logic [4*8*19-1:0] w_r,
    output logic w_vld_o, output logic [4*8*19-1:0] w_y, output logic [4*8-1:0] w_b
);
    logic [16*36*8-1:0] ach [9];
    logic [7:0] b2v, fvo, wvo;
    assign ach[0] = act;
    for (genvar c = 0; c < 8; c++) begin : g_c
        logic [8*81+4:0]   pfc;
        logic [8*79+2:0]   pwc;
        logic [4*8*17-1:0] src, fyc;
        logic [4*8-1:0]    fbc;
        logic [4*19-1:0]   wrc, wyc;
        logic [3:0]        wbc;
        logic [16*8-1:0]   b2c;
        assign pfc[8*81 +: 5] = pf[64*81 +: 5];
        assign pwc[8*79 +: 3] = pw[64*79 +: 3];
        for (genvar k = 0; k < 8; k++) begin : g_k
            assign pfc[81*k +: 81] = pf[81*(8*c+k) +: 81];
            assign pwc[79*k +: 79] = pw[79*(8*c+k) +: 79];
        end
        for (genvar q = 0; q < 4; q++) begin : g_q
            for (genvar i = 0; i < 8; i++) begin : g_i
                assign src[17*(8*q+i) +: 17] = s_rd[17*(64*q+8*c+i) +: 17];
                assign f_y[17*(64*q+8*c+i) +: 17] = fyc[17*(8*q+i) +: 17];
                assign f_b[64*q+8*c+i] = fbc[8*q+i];
            end
            assign wrc[19*q +: 19] = w_r[19*(8*q+c) +: 19];
            assign w_y[19*(8*q+c) +: 19] = wyc[19*q +: 19];
            assign w_b[8*q+c] = wbc[q];
        end
        for (genvar r = 0; r < 16; r++) begin : g_r
            assign b2[64*r + 8*c +: 8] = b2c[8*r +: 8];
        end
        logic [16*36*8-1:0] aci;
`ifdef QBC_MUT_FT
        assign aci = (c == 5) ? ach[c] ^ (4608'd1 << 1000) : ach[c];   // mutant: one act bit broken before column 5
`else
        assign aci = ach[c];
`endif
        qb_col_blk u_col (.clk, .rst_n, .cd(cd[288*c +: 288]), .ctl, .act(aci), .t2(t2[136*c +: 136]),
            .act_o(ach[c+1]), .b2(b2c), .b2_vld(b2v[c]), .f_vld, .f_src, .f_sh, .p_ld, .pf(pfc), .s_rd(src),
            .f_vld_o(fvo[c]), .f_y(fyc), .f_b(fbc), .w_vld, .w_sh, .w_ld, .pw(pwc), .w_r(wrc), .w_vld_o(wvo[c]),
            .w_y(wyc), .w_b(wbc));
    end
    assign b2_vld = b2v[0]; assign f_vld_o = fvo[0]; assign w_vld_o = wvo[0];
endmodule
