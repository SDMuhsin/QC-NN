// qb_lane_s: area variants of the PPU requant lane qb_lane_n (qc18bacc/results/lane.md), all one output per cycle,
// fully pipelined, hierarchical (one sub-module per function so DC report_area -hierarchy gives the breakdown).
//
// qbs_base: the qb_lane structure (S0 inputs -> S1 product, h + r, x >= T -> S2 round-shift, clamp -> S3 + (h + r),
//   saturate, compare; latency 4, h / r / T / sh delivered with x and carried) generalised:
//     shift s = SB + sh (sh SHW bits; SHW = 0: constant shift SB, no shifter), CLAMP = 1: y clamped to 18 b (any
//     input exact, = qb_lane), CLAMP = 0: y truncated to 18 b (exact for |y| < 2^17, the measured in-scope domains),
//     PASS = 1: sh is a per-pass register (port sh loaded when ld = 1, not pipelined).
//   qbs_base #(16, 27, 17, 6, 0, 1, 0) == qb_lane_n (same function, same pipeline).
// qbs_new: 3 register stages, operands delivered at the stage that consumes them (no carried h / r / T / sh flops):
//     cycle n:     vld, mode, x, m        -> S0 registers (edge n)
//     cycle n + 1: h, r, t, sh            -> L registers (edge n + 1), in parallel with the product register S1
//     outputs after edge n + 2 (latency 3, one cycle less than qb_lane).
//   S1: P = x * m (mode 1: m forced to 2^SB, i.e. P = x 2^SB); only bits [SB - 1, SB + 2^SHW - 1 + YW] of P are
//       registered when CLAMP = 0 (all bits >= SB - 1 when CLAMP = 1).
//   S2: q = P >>> (SB - 1 + sel) (sel = mode ? 0 : sh), rounding bit q[0], y = q >>> 1 (18 b, truncated or clamped);
//       sum = y + h + r + q[0] + mode (h, r forced to 0 in mode 1) in 19 b == (x m + 2^(s-1)) >> s + h + r (mode 0)
//       or x + 1 (mode 1);  y_sat = sat(sum, +-32767);  b = y_sat > T  (mode 1: x + 1 > T <=> x >= T);  y_o = mode ? 0 : y_sat.
//   The rounding constant is the carry-in q[0] of the 3-operand add (no separate incrementer).
//   Mode-1 contract: |x| < 32767 (c1 accumulator, <= 750 measured).  TW = 16 contract: T clamped to [-32768, 32767] by
//   the compiler (exact: y_sat in [-32767, 32767]; mode-1 x + 1 in (-32767, 32767)).
// rst_n: synchronous, clears the valid pipeline only.

module qbs_reg #(parameter int W = 1) (input logic clk, input logic [W-1:0] d, output logic [W-1:0] q);
    always_ff @(posedge clk) q <= d;
endmodule

module qbs_rege #(parameter int W = 1) (input logic clk, en, input logic [W-1:0] d, output logic [W-1:0] q);
    always_ff @(posedge clk) if (en) q <= d;
endmodule

module qbs_mul #(parameter int XW = 16, MW = 27, SB = 1, FORCE = 0) (
    input  logic signed [XW-1:0]    x,
    input  logic        [MW-1:0]    m,
    input  logic                    md,
    output logic signed [XW+MW-1:0] p
);
    logic [MW-1:0] me;
    assign me = (FORCE != 0 && md) ? MW'(1) << SB : m;
    assign p  = x * $signed({1'b0, me});
endmodule

// ------------------------------------------------------------------------------------------------ qbs_base
module qbs_hr #(parameter int XW = 16, TW = 17) (
    input  logic signed [15:0] h, r, input logic signed [XW-1:0] x, input logic signed [TW-1:0] t,
    output logic signed [16:0] hr, output logic c
);
    localparam int CW = (XW > TW ? XW : TW) + 1;
    assign hr = 17'(h) + 17'(r);
    assign c  = CW'(x) >= CW'(t);
endmodule

module qbs_rsh #(parameter int PWD = 43, SHW = 6, SB = 0, CLAMP = 1) (
    input  logic signed [PWD-1:0]       p,
    input  logic        [(SHW>0?SHW:1)-1:0] sh,
    output logic signed [17:0]          y2
);
    always_comb begin
        logic signed [PWD-1:0] q;
        logic signed [PWD:0]   y;
        logic        [6:0]     s;
        s = 7'(SB) + ((SHW > 0) ? 7'(sh) : 7'd0);
        q = p >>> (s - 7'd1);
        y = ((PWD+1)'(q) + (PWD+1)'(1)) >>> 1;
        if (CLAMP != 0) begin
            if      (y > (PWD+1)'(131071))  y2 = 18'sd131071;
            else if (y < -(PWD+1)'(131072)) y2 = -18'sd131072;
            else                            y2 = 18'(y);
        end else y2 = 18'(y);
    end
endmodule

module qbs_s3 #(parameter int TW = 17) (
    input  logic signed [17:0] y2, input logic signed [16:0] hr, input logic signed [TW-1:0] t,
    input  logic md, c,
    output logic signed [15:0] y, output logic b
);
    localparam int CW = (TW > 16 ? TW : 16) + 1;
    always_comb begin
        logic signed [18:0] s;
        logic signed [15:0] ys;
        s = 19'(y2) + 19'(hr);
        if      (s >  19'sd32767) ys = 16'sd32767;
        else if (s < -19'sd32767) ys = -16'sd32767;
        else                      ys = 16'(s);
        y = md ? 16'sd0 : ys;
        b = md ? c : (CW'(ys) > CW'(t));
    end
endmodule

module qbs_base #(
    parameter int XW = 16, MW = 27, TW = 17, SHW = 6, SB = 0, CLAMP = 1, PASS = 0
) (
    input  logic                 clk, rst_n, vld, mode, ld,
    input  logic signed [XW-1:0] x,
    input  logic        [MW-1:0] m,
    input  logic        [(SHW>0?SHW:1)-1:0] sh,
    input  logic signed [15:0]   h, r,
    input  logic signed [TW-1:0] t,
    output logic                 vld_o,
    output logic signed [15:0]   y_o,
    output logic                 b_o
);
    localparam int PWD = XW + MW;
    localparam int SW = SHW > 0 ? SHW : 1;
    localparam int NI = 2 + XW + MW + 32 + TW;            // S0 data inputs (md, v, x, m, h, r, t)
    // S0 input registers (sh: per element in u_rin_sh, or the pass register)
    logic                 v0, md0;
    logic signed [XW-1:0] x0;
    logic        [MW-1:0] m0;
    logic signed [15:0]   h0, r0;
    logic signed [TW-1:0] t0;
    logic        [SW-1:0] sh0, sh1;
    qbs_reg #(NI) u_rin (.clk, .d({rst_n & vld, mode, x, m, h, r, t}), .q({v0, md0, x0, m0, h0, r0, t0}));
    if (SHW > 0 && PASS == 0) begin : g_shc
        qbs_reg #(SW) u_rin_sh (.clk, .d(sh), .q(sh0));
        qbs_reg #(SW) u_rc_sh  (.clk, .d(sh0), .q(sh1));     // carried to S2
    end else if (SHW > 0) begin : g_shp
        qbs_rege #(SW) u_rpass (.clk, .en(ld), .d(sh), .q(sh1));   // per-pass register, consumed at S2
    end else begin : g_shk
        assign sh1 = '0;
    end
    // S1
    logic signed [PWD-1:0] prod, p1;
    logic signed [16:0]    hr, hr1, hr2;
    logic                  c, c1, c2, v1, v2, md1, md2;
    logic signed [TW-1:0]  t1, t2;
    qbs_mul #(XW, MW, 1, 0) u_mul (.x(x0), .m(m0), .md(1'b0), .p(prod));
    qbs_hr  #(XW, TW)       u_hr  (.h(h0), .r(r0), .x(x0), .t(t0), .hr, .c);
    qbs_reg #(PWD)          u_rp1 (.clk, .d(prod), .q(p1));
    qbs_reg #(17 + 1 + 1 + TW + 1) u_rc1 (.clk, .d({hr, c, md0, t0, rst_n & v0}), .q({hr1, c1, md1, t1, v1}));
    // S2
    logic signed [17:0] y2c, y2;
    qbs_rsh #(PWD, SHW, SB, CLAMP) u_rsh (.p(p1), .sh(sh1), .y2(y2c));
    qbs_reg #(18)                   u_ry2 (.clk, .d(y2c), .q(y2));
    qbs_reg #(17 + 1 + 1 + TW + 1)  u_rc2 (.clk, .d({hr1, c1, md1, t1, rst_n & v1}), .q({hr2, c2, md2, t2, v2}));
    // S3
    logic signed [15:0] yo;
    logic               bo;
    qbs_s3 #(TW)        u_s3  (.y2, .hr(hr2), .t(t2), .md(md2), .c(c2), .y(yo), .b(bo));
    qbs_reg #(18)       u_rout (.clk, .d({rst_n & v2, yo, bo}), .q({vld_o, y_o, b_o}));
endmodule

// ------------------------------------------------------------------------------------------------ qbs_new
module qbs_fin #(parameter int NP = 35, SHW = 4, TW = 16, YW = 18, CLAMP = 0) (
    input  logic signed [NP-1:0]            p,      // P >>> (SB - 1)
    input  logic        [(SHW>0?SHW:1)-1:0] sh,
    input  logic                            md,
    input  logic signed [15:0]              h, r,
    input  logic signed [TW-1:0]            t,
    output logic signed [15:0]              y,
    output logic                            b
);
    localparam int CW = (TW > 16 ? TW : 16) + 1;
    always_comb begin
        logic signed [NP-1:0] q;
        logic signed [NP-1:0] yq;
        logic signed [17:0]   y18;
        logic signed [18:0]   s;
        logic signed [15:0]   ys;
        q = (SHW > 0 && !md) ? p >>> sh : p;
        yq = q >>> 1;
        if (CLAMP != 0) begin
            if      (yq > NP'(131071))  y18 = 18'sd131071;
            else if (yq < -NP'(131072)) y18 = -18'sd131072;
            else                        y18 = 18'(yq);
        end else y18 = 18'(yq);
        s = 19'(y18) + (md ? 19'sd0 : 19'(h)) + (md ? 19'sd0 : 19'(r)) + 19'(q[0]) + 19'(md);
        if      (s >  19'sd32767) ys = 16'sd32767;
        else if (s < -19'sd32767) ys = -16'sd32767;
        else                      ys = 16'(s);
        y = md ? 16'sd0 : ys;
        b = CW'(ys) > CW'(t);
    end
endmodule

module qbs_new #(
    parameter int XW = 16, MW = 27, TW = 16, SHW = 4, SB = 9, CLAMP = 0, PASS = 0
) (
    input  logic                 clk, rst_n, vld, mode, ld,
    input  logic signed [XW-1:0] x,                      // cycle n
    input  logic        [MW-1:0] m,
    input  logic        [(SHW>0?SHW:1)-1:0] sh,          // cycle n + 1 (PASS: pass register, loaded when ld)
    input  logic signed [15:0]   h, r,
    input  logic signed [TW-1:0] t,
    output logic                 vld_o,
    output logic signed [15:0]   y_o,
    output logic                 b_o
);
    localparam int PWD = XW + MW;
    localparam int SW = SHW > 0 ? SHW : 1;
    localparam int YW = 18;
    // registered product bits: [SB - 1, SB - 1 + NP)
    localparam int NPT = (1 << SHW) - 1 + YW + 1;
    localparam int NP = (CLAMP != 0) ? PWD - SB + 1 : (NPT < PWD - SB + 1 ? NPT : PWD - SB + 1);
    logic                 v0, md0, v1, md1;
    logic signed [XW-1:0] x0;
    logic        [MW-1:0] m0;
    qbs_reg #(2 + XW + MW) u_rin (.clk, .d({rst_n & vld, mode, x, m}), .q({v0, md0, x0, m0}));
    // late operands (cycle n + 1)
    logic signed [15:0]   h1, r1;
    logic signed [TW-1:0] t1;
    logic        [SW-1:0] sh1;
    qbs_reg #(32 + TW) u_rlate (.clk, .d({h, r, t}), .q({h1, r1, t1}));
    if (SHW > 0 && PASS == 0) begin : g_shc
        qbs_reg #(SW) u_rlate_sh (.clk, .d(sh), .q(sh1));
    end else if (SHW > 0) begin : g_shp
        qbs_rege #(SW) u_rpass (.clk, .en(ld), .d(sh), .q(sh1));
    end else begin : g_shk
        assign sh1 = '0;
    end
    // S1: product
    logic signed [PWD-1:0] prod;
    logic signed [PWD:0]   prode;
    logic signed [NP-1:0]  p1;
    qbs_mul #(XW, MW, SB, 1) u_mul (.x(x0), .m(m0), .md(md0), .p(prod));
    assign prode = {prod[PWD-1], prod};
    qbs_reg #(NP + 2) u_rp1 (.clk, .d({rst_n & v0, md0, NP'(prode >>> (SB - 1))}), .q({v1, md1, p1}));
    // S2: window select, + h + r + round, saturate, compare
    logic signed [15:0] yo;
    logic               bo;
    qbs_fin #(NP, SHW, TW, YW, CLAMP) u_fin (.p(p1), .sh(sh1), .md(md1), .h(h1), .r(r1), .t(t1), .y(yo), .b(bo));
    qbs_reg #(18) u_rout (.clk, .d({rst_n & v1, yo, bo}), .q({vld_o, y_o, b_o}));
endmodule

// ------------------------------------------------------------------------------------------------ synthesis tops
// `QBS_TOP(name, module, XW, MW, TW, SHW, SB, CLAMP, PASS)
`define QBS_TOP(NAME, MOD, XW_, MW_, TW_, SHW_, SB_, CL_, PS_) \
module NAME ( \
    input  logic clk, rst_n, vld, mode, ld, \
    input  logic signed [XW_-1:0] x, \
    input  logic        [MW_-1:0] m, \
    input  logic        [((SHW_)>0?(SHW_):1)-1:0] sh, \
    input  logic signed [15:0] h, r, \
    input  logic signed [TW_-1:0] t, \
    output logic vld_o, \
    output logic signed [15:0] y_o, \
    output logic b_o \
); \
    MOD #(.XW(XW_), .MW(MW_), .TW(TW_), .SHW(SHW_), .SB(SB_), .CLAMP(CL_), .PASS(PS_)) u_lane (.*); \
endmodule

`QBS_TOP(qb_lane_h,    qbs_base, 16, 27, 17, 6, 0, 1, 0)   // = qb_lane_n, hierarchical (step-1 breakdown)
`QBS_TOP(qb_lane_sa,   qbs_base, 16, 27, 16, 4, 9, 0, 0)   // (a) widths: T 16 b, shift 4 b window s in [9, 24], y unclamped
`QBS_TOP(qb_lane_sb,   qbs_base, 16, 34, 16, 4, 9, 0, 1)   // (b) per-pass shift window (4 b pass reg), common-shift MW 34
`QBS_TOP(qb_lane_sb28, qbs_base, 16, 28, 16, 4, 9, 0, 1)   // (b) MW 28: exact without the s0 stem only
`QBS_TOP(qb_lane_sbk,  qbs_base, 16, 36, 16, 0, 24, 0, 1)  // (b) one network-wide constant shift 24, MW 36, no shifter
`QBS_TOP(qb_lane_sc,   qbs_new,  16, 27, 17, 6, 1, 1, 0)   // (c) late operands, 3 stages, baseline widths / clamp
`QBS_TOP(qb_lane_s,    qbs_new,  16, 27, 16, 4, 9, 0, 0)   // (a) + (c): per-channel 4 b shift window, MW 27
`QBS_TOP(qb_lane_s8,   qbs_new,  16, 29, 16, 3, 17, 0, 0)  // (a) + (c), 3 b shift window s in [17, 24], MW 29
`QBS_TOP(qb_lane_sk,   qbs_new,  16, 36, 16, 0, 24, 0, 1)  // (a) + (b) + (c), constant shift 24, MW 36
`QBS_TOP(qb_lane_sp,   qbs_new,  16, 34, 16, 4, 9, 0, 1)   // (a) + (b) + (c), per-pass 4 b window, MW 34
