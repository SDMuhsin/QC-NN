// qb_core: compute core of QC18B-ACC (ARCH.md v1.2, RTL plan R1).
//   16 x 8 PEs (qbc_pe: qb_pe extended to KB 36, ACC_W 20, stem group-shift mode, per-PE b2 comparators at capture,
//   shadow capture + drain), 8 x 36 code decoders (qbc_dec, table = compile/program.py DEC) with one broadcast
//   register stage per 8-row group, 256 fused lanes (qbf_lane = qb_lane_fn: MW 28, sel 4 b, no pre-clamp) and
//   32 wide lanes (qbcw_lane = qb_lane_w + sign / bias pre-add / ReLU / u8 clamp / 19-b r), per-channel parameter
//   banks.  Pure datapath: every control is given per cycle at the ports (the R3 sequencer generates them).
//
// ---------------------------------------------------------------- array side (timing relative to item n)
//   cycle n-1  code port: cd[col][j] (8 cols x 36 x 8 b) + ctl {valid, first, plane[2:0], neg, stem, g3n, cap, cmp}
//              -> 288 decoders + per-column nneg-weight NNw -> broadcast registers BR (one copy per 8-row group)
//   cycle n    act port: act[row] (16 x 36 bytes; byte j = tap * 4 + group, bit = channel in group; 1x1: byte j =
//              channel group j)  -> PE S0 input registers (a, c, NNw, ctl)
//   S1 (edge n+1): per lane i, group g (9 bytes j = 4 t + g, 18 terms): u_gi = popcount(x), x = t!=0 & (a ^ t==-1)
//              s_i = sum_g w_g u_gi - NNw,  w = (1,1,1,1) binary/int8 planes,  (1,2,4,+-8) stem (8 negated when
//              g3n: image plane 7 = group 3 of the second stem cycle), NNw = sum_g w_g #(t == -1 in group g)
//              (column-wide, computed once per column at the decoders);  registered s_i (10 b signed, |s| <= 270)
//   S2 (edge n+2): acc_i = (first ? 0 : acc_i) +/- (s_i << plane) (neg: two's-complement MSB plane), mod 2^20;
//              cap: shadow <= acc (value before this cycle's term);  cmp: b2_i <= (acc_i >= T'_i) ^ inv_i
//   cycle n+1  T2 port: t2[col] = 8 x {inv, T'[15:0]} of the tile whose cmp was issued at n-1 (sign(g) folded by the
//              compiler: sgn +1: T' = T2, inv 0;  sgn -1: T' = clamp16(1 - T2), inv 1) -> per-group register
//   outputs    b2 (1024 b, PE (r, c) lane i at bit 64 r + 8 c + i) valid in cycle n+3 with b2_vld.
//   stem items: cycle h = 0, 1: group g of byte j carries image plane 4h + g; codes of group 0 replicated into all
//              4 groups by the weight store; plane = 4h, neg = 0, stem = 1, g3n = (h == 1).
// ---------------------------------------------------------------- PPU side (timing relative to port cycle t)
//   fused: f_vld, f_src (0 shadow, 1 s_rd = hm job), f_sh (row shift), p_ld (load bank P0 from pf) at t; registered
//          at the boundary -> lane cycle e = t + 1: lane (q, c, i) (index 64 q + 8 c + i) takes PE (q, c) shadow[i]
//          (rows 0..3; f_sh shifts shadow rows r <- r + 4 at the end of e: 4 drain cycles per tile) or s_rd (hm);
//          late operands (s_rd as sv, P1 = late fields of P0 copied at the end of the cycle after p_ld) at e + 1;
//          outputs f_vld_o / f_y (17 b: s_out / r / u8) / f_b (b1_next) valid in cycle e + 3.
//   wide:  w_vld, w_sh (chain shift), w_ld (load bank W from pw) at t -> lane cycle e = t + 1: wide lane (q, c)
//          (index 8 q + c) takes PE (q, c) sh_out = shadow[7]; w_sh shifts the lane-serial chain
//          (shadow[0] <- PE (q + 4, c).sh_out, shadow[i] <- shadow[i - 1]) and rotates the column's 8 bank records:
//          32 drain cycles per tile, step k: channel 8 c + 7 - k % 8, row q + 4 (k / 8);  r (19 b) at e + 1;
//          outputs w_vld_o / w_y (19 b) / w_b valid in cycle e + 4.
// rst_n: synchronous, clears valid / capture / compare / shift pipelines only.

// ================================================================================================ helpers
module qbc_reg #(parameter int W = 1) (input logic clk, input logic [W-1:0] d, output logic [W-1:0] q);
    always_ff @(posedge clk) q <= d;
endmodule

// ================================================================================================ column decode
// 36 decoders of one column + the column's nneg weight NNw (computed once, broadcast with the codes).
module qbc_coldec #(parameter int KB = 36) (
    input  logic [KB*8-1:0]   cd,
    input  logic              stem, g3n,
    output logic [KB*10-1:0]  c,
    output logic signed [9:0] nnw
);
    for (genvar j = 0; j < KB; j++) begin : g_d
`ifdef QBC_MUT_DEC
        qbc_dec u_dec (.code(j == 0 ? 8'd0 : cd[8*j +: 8]), .pe(c[10*j +: 10]));     // mutant: byte 0 dropped
`else
        qbc_dec u_dec (.code(cd[8*j +: 8]), .pe(c[10*j +: 10]));
`endif
    end
    always_comb begin
        logic [4:0] nn [4];
        for (int g = 0; g < 4; g++) nn[g] = '0;
        for (int j = 0; j < KB; j++)
            nn[j % 4] = nn[j % 4] + 5'(c[10*j+5 +: 2] == 2'b11) + 5'(c[10*j +: 2] == 2'b11);
`ifdef QBC_MUT_NNW
        if (0)
`else
        if (stem)
`endif
                  nnw = 10'(nn[0]) + 10'({nn[1], 1'b0}) + 10'({nn[2], 2'b0}) + (g3n ? -10'({nn[3], 3'b0})
                                                                                    : 10'({nn[3], 3'b0}));
        else      nnw = 10'(nn[0]) + 10'(nn[1]) + 10'(nn[2]) + 10'(nn[3]);
    end
endmodule

// broadcast register of one column for one 8-row group: decoded codes, NNw, item controls, T2
module qbc_br #(parameter int KB = 36) (
    input  logic              clk, rst_n,
    input  logic [KB*10-1:0]  c,
    input  logic signed [9:0] nnw,
    input  logic [9:0]        ctl,          // {cmp, cap, g3n, stem, neg, plane[2:0], first, valid}
    input  logic [8*17-1:0]   t2,
    output logic [KB*10-1:0]  c_q,
    output logic signed [9:0] nnw_q,
    output logic [9:0]        ctl_q,
    output logic [8*17-1:0]   t2_q
);
    always_ff @(posedge clk) begin
        c_q <= c; nnw_q <= nnw; t2_q <= t2;
        ctl_q <= rst_n ? ctl : {ctl[9:8] & 2'b00, ctl[7:1], 1'b0};
    end
endmodule

// ================================================================================================ PE
module qbc_pe #(parameter int KB = 36, parameter int ACC_W = 20) (
    input  logic                clk, rst_n,
    input  logic [KB*8-1:0]     a,
    input  logic [KB*10-1:0]    c,
    input  logic signed [9:0]   nnw,
    input  logic [9:0]          ctl,        // {cmp, cap, g3n, stem, neg, plane[2:0], first, valid}
    input  logic [8*17-1:0]     t2,         // per lane {inv, T'[15:0]}, used at S2 (register outside, per group)
    input  logic                fsh, wsh,   // drain shifts (act at this edge)
    input  logic [8*ACC_W-1:0]  up,         // PE (r + 4) shadow (fused row shift)
    input  logic [ACC_W-1:0]    sh_in,      // PE (r + 4) sh_out (wide chain)
    output logic [8*ACC_W-1:0]  shd,
    output logic [ACC_W-1:0]    sh_out,
    output logic [7:0]          b2
);
    // ---- S0: input registers
    logic [KB*8-1:0]   a_q;
    logic [KB*10-1:0]  c_q;
    logic signed [9:0] nnw_q;
    logic [9:0]        ctl_q;
    qbc_pe_in #(KB) u_in (.clk, .rst_n, .a, .c, .nnw, .ctl, .a_q, .c_q, .nnw_q, .ctl_q);
    // ---- S1: group popcounts, weighted sum, - NNw
    logic [8*10-1:0] s_q;
    logic [7:0]      ctl_p;     // {cmp, cap, neg, plane[2:0], first, valid}
    qbc_pe_pop #(KB) u_pop (.clk, .a(a_q), .c(c_q), .nnw(nnw_q), .stem(ctl_q[6]), .g3n(ctl_q[7]), .s_q);
    always_ff @(posedge clk) ctl_p <= rst_n ? {ctl_q[9:8], ctl_q[5:0]} : {2'b00, ctl_q[5:1], 1'b0};
    // ---- S2: accumulators, comparators, shadow
    logic [8*ACC_W-1:0] acc;
    qbc_pe_acc #(ACC_W) u_acc (.clk, .s(s_q), .plane(ctl_p[4:2]), .neg(ctl_p[5]), .first(ctl_p[1]),
                               .valid(ctl_p[0]), .acc);
    qbc_pe_cmp #(ACC_W) u_cmp (.clk, .acc, .cmp(ctl_p[7]), .t2, .b2);
    qbc_pe_shd #(ACC_W) u_shd (.clk, .acc, .cap(ctl_p[6]), .fsh, .wsh, .up, .sh_in, .shd);
    assign sh_out = shd[7*ACC_W +: ACC_W];
endmodule

module qbc_pe_in #(parameter int KB = 36) (
    input  logic clk, rst_n,
    input  logic [KB*8-1:0] a, input logic [KB*10-1:0] c, input logic signed [9:0] nnw, input logic [9:0] ctl,
    output logic [KB*8-1:0] a_q, output logic [KB*10-1:0] c_q, output logic signed [9:0] nnw_q,
    output logic [9:0] ctl_q
);
    always_ff @(posedge clk) begin
        a_q <= a; c_q <= c; nnw_q <= nnw;
        ctl_q <= rst_n ? ctl : {2'b00, ctl[7:1], 1'b0};
    end
endmodule

module qbc_pe_pop #(parameter int KB = 36) (
    input  logic               clk,
    input  logic [KB*8-1:0]    a,
    input  logic [KB*10-1:0]   c,
    input  logic signed [9:0]  nnw,
    input  logic               stem, g3n,
    output logic [8*10-1:0]    s_q
);
    localparam int NG = KB / 4;          // bytes per group (9)
    logic [2*NG-1:0] x [8][4];           // x[i][g][term]
    always_comb begin
        for (int j = 0; j < KB; j++) begin
            for (int n = 0; n < 2; n++) begin
                logic [2:0]  k;
                logic [1:0]  t;
                logic [15:0] aa;
                logic [7:0]  rot;
                k = (n == 0) ? c[10*j+7 +: 3] : c[10*j+2 +: 3];
                t = (n == 0) ? c[10*j+5 +: 2] : c[10*j+0 +: 2];
                aa  = {a[8*j +: 8], a[8*j +: 8]};
                rot = aa[k +: 8];                     // rot[i] = a[(i + k) mod 8]
                for (int i = 0; i < 8; i++) x[i][j % 4][2*(j/4)+n] = t[0] & (rot[i] ^ t[1]);
            end
        end
    end
    logic signed [9:0] s [8];
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            logic [4:0] u [4];
            for (int g = 0; g < 4; g++) u[g] = 5'($countones(x[i][g]));
            if (stem) s[i] = 10'(u[0]) + 10'({u[1], 1'b0}) + 10'({u[2], 2'b0})
`ifdef QBC_MUT_G3N
                           + 10'({u[3], 3'b0}) - nnw;                                  // mutant: plane 7 positive
`else
                           + (g3n ? -10'({u[3], 3'b0}) : 10'({u[3], 3'b0})) - nnw;
`endif
            else      s[i] = 10'(u[0]) + 10'(u[1]) + 10'(u[2]) + 10'(u[3]) - nnw;
        end
    end
    always_ff @(posedge clk) for (int i = 0; i < 8; i++) s_q[10*i +: 10] <= s[i];
endmodule

module qbc_pe_acc #(parameter int ACC_W = 20) (
    input  logic                clk,
    input  logic [8*10-1:0]     s,
    input  logic [2:0]          plane,
    input  logic                neg, first, valid,
    output logic [8*ACC_W-1:0]  acc
);
    always_ff @(posedge clk) begin
        for (int i = 0; i < 8; i++) begin
            if (valid) begin
                logic [ACC_W-1:0] sv, base;
                sv   = ACC_W'($signed(s[10*i +: 10])) << plane;   // sign-extended, then shifted (mod 2^ACC_W)
                base = first ? '0 : acc[ACC_W*i +: ACC_W];
                acc[ACC_W*i +: ACC_W] <= base + (sv ^ {ACC_W{neg}}) + ACC_W'(neg);
            end
        end
    end
endmodule

// per-PE b2 comparators (8): b2_i = (acc_i >= T'_i) ^ inv_i at cmp (acc before this cycle's term, as capture)
module qbc_pe_cmp #(parameter int ACC_W = 20) (
    input  logic                clk,
    input  logic [8*ACC_W-1:0]  acc,
    input  logic                cmp,
    input  logic [8*17-1:0]     t2,
    output logic [7:0]          b2
);
    always_ff @(posedge clk)
        if (cmp) for (int i = 0; i < 8; i++)
`ifdef QBC_MUT_INV
            b2[i] <= ($signed(acc[ACC_W*i +: ACC_W]) >= $signed(t2[17*i +: 16]));          // mutant: no inv
`else
            b2[i] <= ($signed(acc[ACC_W*i +: ACC_W]) >= $signed(t2[17*i +: 16])) ^ t2[17*i+16];
`endif
endmodule

// shadow: capture (priority) / fused row shift (8 lanes in parallel from PE r + 4) / wide lane-serial chain
module qbc_pe_shd #(parameter int ACC_W = 20) (
    input  logic                clk,
    input  logic [8*ACC_W-1:0]  acc,
    input  logic                cap, fsh, wsh,
    input  logic [8*ACC_W-1:0]  up,
    input  logic [ACC_W-1:0]    sh_in,
    output logic [8*ACC_W-1:0]  shd
);
    always_ff @(posedge clk) begin
        if (cap)      shd <= acc;
        else if (fsh) shd <= up;
        else if (wsh) shd <= {shd[0 +: 7*ACC_W], sh_in};
    end
endmodule

// ================================================================================================ wide lane
// qb_lane_w (qb_lane #(20, 31, 21)) extended (ARCH v1.2 / cycles.md deviations 2-4): pre: x = (sgn ? -acc : acc)
// + bias (20 b), ReLU (pool / hm mode), x 20 b (compiler contract); y = (x m + 2^(sh-1)) >> sh clamped to 19 b;
// omode 0 sat: y_o = sat(y + r, +-32767), b = y_o > T;  1 r: y_o = y + r (19 b contract);  2 u8: clamp(y, 0, 127).
// r (19 b) is a late operand (cycle n + 1, the stream read); everything else at cycle n.  Latency 4.
module qbcw_lane #(parameter int XW = 20, MW = 31, TW = 21, RW = 19, YW = 19) (
    input  logic                 clk, rst_n, vld, relu, sgn,
    input  logic signed [19:0]   acc,
    input  logic signed [XW-1:0] bias,
    input  logic        [MW-1:0] m,
    input  logic        [5:0]    sh,
    input  logic        [1:0]    omode,
    input  logic signed [TW-1:0] t,
    input  logic signed [RW-1:0] r,              // cycle n + 1
    output logic                 vld_o,
    output logic signed [YW-1:0] y_o,
    output logic                 b_o
);
    localparam int PWD = XW + MW;
    // S0: pre-processing + input registers
    logic signed [XW-1:0] xp, x0;
    always_comb begin
        logic signed [XW+1:0] aa;
        aa = sgn ? -(XW+2)'(acc) : (XW+2)'(acc);
        aa = aa + (XW+2)'(bias);
        if (relu && aa < 0) aa = '0;
        xp = XW'(aa);
    end
    logic        [MW-1:0] m0;
    logic        [5:0]    sh0;
    logic        [1:0]    om0;
    logic signed [TW-1:0] t0;
    logic                 v0;
    always_ff @(posedge clk) begin
        x0 <= xp; m0 <= m; sh0 <= sh; om0 <= omode; t0 <= t;
        v0 <= rst_n ? vld : 1'b0;
    end
    // S1: product, r (late)
    logic signed [PWD-1:0] prod, p1;
    logic signed [RW-1:0]  r1;
    logic        [5:0]     sh1;
    logic        [1:0]     om1;
    logic signed [TW-1:0]  t1;
    logic                  v1;
    assign prod = x0 * $signed({1'b0, m0});
    always_ff @(posedge clk) begin
        p1 <= prod; r1 <= r; sh1 <= sh0; om1 <= om0; t1 <= t0;
        v1 <= rst_n ? v0 : 1'b0;
    end
    // S2: round-shift, clamp to YW b
    logic signed [YW-1:0] y2;
    logic signed [RW-1:0] r2;
    logic        [1:0]    om2;
    logic signed [TW-1:0] t2;
    logic                 v2;
    always_ff @(posedge clk) begin
        logic signed [PWD-1:0] q;
        logic signed [PWD:0]   y;
        q = p1 >>> (sh1 - 6'd1);
        y = ((PWD+1)'(q) + (PWD+1)'(1)) >>> 1;
        if      (y > (PWD+1)'((1 << (YW-1)) - 1)) y2 <= YW'((1 << (YW-1)) - 1);
        else if (y < -(PWD+1)'(1 << (YW-1)))      y2 <= YW'(-(1 << (YW-1)));
        else                                       y2 <= YW'(y);
        r2 <= r1; om2 <= om1; t2 <= t1;
        v2 <= rst_n ? v1 : 1'b0;
    end
    // S3: + r, output modes, compare
    always_ff @(posedge clk) begin
        logic signed [YW:0]   s;
        logic signed [15:0]   ys;
        s = (YW+1)'(y2) + (YW+1)'(r2);
        if      (s >  (YW+1)'(32767)) ys = 16'sd32767;
        else if (s < -(YW+1)'(32767)) ys = -16'sd32767;
        else                          ys = 16'(s);
        case (om2)
            2'd0:    y_o <= YW'(ys);
            2'd1:    y_o <= YW'(s);
            default: y_o <= (y2 < 0) ? YW'(0) : (y2 > $signed(YW'(127))) ? YW'(127) : y2;
        endcase
        b_o   <= (om2 == 2'd0) && ((TW+1)'(ys) > (TW+1)'(t2));
        vld_o <= rst_n ? v2 : 1'b0;
    end
endmodule

// ================================================================================================ parameter banks
// fused bank: 64 channel records; P0 = all fields (early ones used at lane cycle e), P1 = late fields copied from P0
// one cycle after the load (used at e + 1), so back-to-back drains / hm jobs never overwrite a late operand.
//   pf record (per channel, 81 b): {T[15:0], h[15:0], sel[3:0], m[27:0], bias[15:0], sgn};  common (5 b):
//   {omode[1:0], rmode[1:0], relu} at pf[64*81 +: 5]
module qbc_pbank_f #(parameter int NC = 64, MW = 28) (
    input  logic                     clk, ld,
    input  logic [NC*(37+MW+16)+4:0] pf,
    output logic [NC*(1+16+MW)-1:0]  early,      // per channel {m, bias, sgn}
    output logic                     relu,
    output logic [NC*36-1:0]         late,       // per channel {T, h, sel}
    output logic [3:0]               lmode       // {omode, rmode}
);
    localparam int RW = 37 + MW + 16;   // 81 at MW 28
    localparam int EW = 1 + 16 + MW;
    logic [NC*RW+4:0] p0;
    logic             ld1;
    always_ff @(posedge clk) begin
        if (ld) p0 <= pf;
        ld1 <= ld;
        if (ld1) begin
            for (int ch = 0; ch < NC; ch++) late[36*ch +: 36] <= p0[RW*ch + EW +: 36];
            lmode <= p0[NC*RW+1 +: 4];
        end
    end
    always_comb begin
        for (int ch = 0; ch < NC; ch++) early[EW*ch +: EW] = p0[RW*ch +: EW];
        relu = p0[NC*RW];
    end
endmodule

// wide bank: 64 channel records, per column 8 records rotating with the wide chain (slot 7 = current channel).
//   pw record (79 b): {T[20:0], sh[5:0], m[30:0], bias[19:0], sgn};  common (3 b): {omode[1:0], relu} at pw[64*79 +: 3]
module qbc_pbank_w #(parameter int NCOL = 8) (
    input  logic                    clk, ld, rot,
    input  logic [NCOL*8*79+2:0]    pw,
    output logic [NCOL*79-1:0]      cur,        // per column: slot 7
    output logic [2:0]              cmn
);
    logic [79-1:0] rec [NCOL][8];
    always_ff @(posedge clk) begin
        if (ld) begin
            for (int c = 0; c < NCOL; c++) for (int k = 0; k < 8; k++) rec[c][k] <= pw[79*(8*c+k) +: 79];
            cmn <= pw[NCOL*8*79 +: 3];
        end else if (rot) begin
            for (int c = 0; c < NCOL; c++) begin
`ifdef QBC_MUT_ROT
                rec[c][7] <= rec[c][0];                                                    // mutant: reversed
                for (int k = 0; k < 7; k++) rec[c][k] <= rec[c][k+1];
`else
                rec[c][0] <= rec[c][7];
                for (int k = 1; k < 8; k++) rec[c][k] <= rec[c][k-1];
`endif
            end
        end
    end
    always_comb for (int c = 0; c < NCOL; c++) cur[79*c +: 79] = rec[c][7];
endmodule

// ================================================================================================ core
module qb_core #(
    parameter int ROWS = 16,                 // multiple of 8 (one broadcast register per 8-row group), >= 4
    parameter int COLS = 8,
    parameter int KB   = 36,
    parameter int MWF  = 28                  // fused-lane multiplier width
) (
    input  logic                         clk, rst_n,
    // array side
    input  logic [COLS*KB*8-1:0]         cd,         // cycle n-1
    input  logic [9:0]                   ctl,        // cycle n-1: {cmp, cap, g3n, stem, neg, plane[2:0], first, valid}
    input  logic [ROWS*KB*8-1:0]         act,        // cycle n
    input  logic [COLS*8*17-1:0]         t2,         // cycle n+1
    output logic [ROWS*COLS*8-1:0]       b2,
    output logic                         b2_vld,
    // fused lanes (NLF = 4 * COLS * 8)
    input  logic                         f_vld, f_src, f_sh, p_ld,
    input  logic [COLS*8*(37+MWF+16)+4:0] pf,
    input  logic [4*COLS*8*17-1:0]       s_rd,       // late (sv) or early (hm x)
    output logic                         f_vld_o,
    output logic [4*COLS*8*17-1:0]       f_y,        // s_out / r / u8
    output logic [4*COLS*8-1:0]          f_b,        // b1_next
    // wide lanes (NLW = 4 * COLS)
    input  logic                         w_vld, w_sh, w_ld,
    input  logic [COLS*8*79+2:0]         pw,
    input  logic [4*COLS*19-1:0]         w_r,        // late
    output logic                         w_vld_o,
    output logic [4*COLS*19-1:0]         w_y,
    output logic [4*COLS-1:0]            w_b
);
    localparam int AW = 20;
    localparam int NG = ROWS / 8;
    localparam int NLF = 4 * COLS * 8;
    localparam int NLW = 4 * COLS;
    localparam int EW = 1 + 16 + MWF;

    // ---------------------------------------------------------------- decode + broadcast registers
    logic [KB*10-1:0]  cbr  [NG][COLS];
    logic signed [9:0] nbr  [NG][COLS];
    logic [9:0]        kbr  [NG][COLS];
    logic [8*17-1:0]   tbr  [NG][COLS];
    for (genvar c = 0; c < COLS; c++) begin : g_col
        logic [KB*10-1:0]  dc;
        logic signed [9:0] nw;
        qbc_coldec #(KB) u_dec (.cd(cd[KB*8*c +: KB*8]), .stem(ctl[6]), .g3n(ctl[7]), .c(dc), .nnw(nw));
        for (genvar g = 0; g < NG; g++) begin : g_grp
            qbc_br #(KB) u_br (.clk, .rst_n, .c(dc), .nnw(nw), .ctl, .t2(t2[8*17*c +: 8*17]),
                               .c_q(cbr[g][c]), .nnw_q(nbr[g][c]), .ctl_q(kbr[g][c]), .t2_q(tbr[g][c]));
        end
    end

    // ---------------------------------------------------------------- PPU control registers (boundary)
    logic fv_q, fs_q, fsh_q, wv_q, wsh_q;
    logic [NG-1:0] fsh_g, wsh_g;            // per-group copies of the drain shifts
    always_ff @(posedge clk) begin
        fv_q  <= rst_n & f_vld;  fs_q <= f_src;
        fsh_q <= rst_n & f_sh;   wv_q <= rst_n & w_vld;  wsh_q <= rst_n & w_sh;
        fsh_g <= {NG{rst_n & f_sh}};
        wsh_g <= {NG{rst_n & w_sh}};
    end

    // ---------------------------------------------------------------- PE array
    logic [8*AW-1:0] shd  [ROWS][COLS];
    logic [AW-1:0]   sho  [ROWS][COLS];
    for (genvar r = 0; r < ROWS; r++) begin : g_r
        for (genvar c = 0; c < COLS; c++) begin : g_c
            logic [8*AW-1:0] up;
            logic [AW-1:0]   shi;
            if (r + 4 < ROWS) begin : g_up
                assign up = shd[r+4][c];
                assign shi = sho[r+4][c];
            end else begin : g_end
                assign up = '0;
                assign shi = '0;
            end
            qbc_pe #(KB, AW) u_pe (.clk, .rst_n, .a(act[KB*8*r +: KB*8]), .c(cbr[r/8][c]), .nnw(nbr[r/8][c]),
                                   .ctl(kbr[r/8][c]), .t2(tbr[r/8][c]), .fsh(fsh_g[r/8]), .wsh(wsh_g[r/8]), .up,
                                   .sh_in(shi), .shd(shd[r][c]), .sh_out(sho[r][c]), .b2(b2[COLS*8*r + 8*c +: 8]));
        end
    end
    // b2 valid: cmp at S2 (ctl n-1 -> BR n -> S0 n+1 -> S1 n+2 -> b2 at n+3)
    logic [2:0] cmpd;
    always_ff @(posedge clk) cmpd <= rst_n ? {cmpd[1:0], kbr[0][0][9]} : 3'b0;
    assign b2_vld = cmpd[2];

    // ---------------------------------------------------------------- fused lanes
    logic [COLS*8*EW-1:0] fe;
    logic [COLS*8*36-1:0] fl;
    logic                 frelu;
    logic [3:0]           flm;
    qbc_pbank_f #(COLS*8, MWF) u_pbf (.clk, .ld(p_ld), .pf, .early(fe), .relu(frelu), .late(fl), .lmode(flm));
    logic [NLF-1:0] fvo;
    for (genvar q = 0; q < 4; q++) begin : g_fq
        for (genvar c = 0; c < COLS; c++) begin : g_fc
            for (genvar i = 0; i < 8; i++) begin : g_fi
                localparam int L = COLS * 8 * q + 8 * c + i;
                localparam int CH = 8 * c + i;
                logic signed [AW-1:0] x;
                logic signed [16:0]   sv;
                assign sv = s_rd[17*L +: 17];
                assign x  = fs_q ? AW'(sv) : shd[q][c][AW*i +: AW];
                qbf_lane #(.AW(AW), .BW(16), .XW(16), .MW(MWF), .TW(16), .SHW(4), .SB(17), .PC(0)) u_lf (
                    .clk, .rst_n, .vld(fv_q), .relu(frelu), .acc(x), .sgn(fe[EW*CH]),
                    .bias(fe[EW*CH+1 +: 16]), .lo(16'sd0), .hi(16'sd0), .m(fe[EW*CH+17 +: MWF]),
                    .sh(fl[36*CH +: 4]), .h(fl[36*CH+4 +: 16]), .sv, .rmode(flm[1:0]), .omode(flm[3:2]),
                    .t(fl[36*CH+20 +: 16]), .vld_o(fvo[L]), .y_o(f_y[17*L +: 17]), .b_o(f_b[L]));
            end
        end
    end
    assign f_vld_o = fvo[0];

    // ---------------------------------------------------------------- wide lanes
    logic [COLS*79-1:0] wc;
    logic [2:0]         wcm;
    qbc_pbank_w #(COLS) u_pbw (.clk, .ld(w_ld), .rot(wsh_q), .pw, .cur(wc), .cmn(wcm));
    logic [NLW-1:0] wvo;
    for (genvar q = 0; q < 4; q++) begin : g_wq
        for (genvar c = 0; c < COLS; c++) begin : g_wc
            localparam int L = COLS * q + c;
            logic [78:0] pr;
            assign pr = wc[79*c +: 79];
            qbcw_lane u_lw (.clk, .rst_n, .vld(wv_q), .relu(wcm[0]), .sgn(pr[0]), .acc(sho[q][c]),
                            .bias(pr[1 +: 20]), .m(pr[21 +: 31]), .sh(pr[52 +: 6]), .omode(wcm[2:1]),
                            .t(pr[58 +: 21]), .r(w_r[19*L +: 19]), .vld_o(wvo[L]), .y_o(w_y[19*L +: 19]),
                            .b_o(w_b[L]));
        end
    end
    assign w_vld_o = wvo[0];
endmodule

// synthesis tops: qb_core (16 x 8), qb_core_s (8 x 2: same per-element logic, fast timing / glue check)
module qb_core_s (
    input  logic clk, rst_n,
    input  logic [2*36*8-1:0] cd, input logic [9:0] ctl, input logic [8*36*8-1:0] act, input logic [2*8*17-1:0] t2,
    output logic [8*2*8-1:0] b2, output logic b2_vld,
    input  logic f_vld, f_src, f_sh, p_ld, input logic [2*8*81+4:0] pf, input logic [4*2*8*17-1:0] s_rd,
    output logic f_vld_o, output logic [4*2*8*17-1:0] f_y, output logic [4*2*8-1:0] f_b,
    input  logic w_vld, w_sh, w_ld, input logic [2*8*79+2:0] pw, input logic [4*2*19-1:0] w_r,
    output logic w_vld_o, output logic [4*2*19-1:0] w_y, output logic [4*2-1:0] w_b
);
    qb_core #(.ROWS(8), .COLS(2)) u_core (.*);
endmodule
