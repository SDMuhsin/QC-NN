// qb_lane_f: fused PPU lane for the p2 golden (qc18bacc.golden_p2.IntBin2; results/lane.md "qb_lane_f").
// qb_lane_s8 arithmetic (qbs_new: window requant s' = SB + sel, late operands, rounding as carry-in, 3 register stages)
// plus the compiler deviations of results/cycles.md (sign(g) negate, bias pre-add, input ReLU, per-channel pre-clamp,
// [0, 127] output clamp, 17-b r) and the p2 identity residual rs = relu(s_in) >> {0, 1} (round half up, no multiplier).
// No mode 1 (binary c1 compares run on the per-PE comparators, v1.1 change 3).
//
//   cycle n (early):  vld, relu, acc (AW b, raw PE accumulator M x), sgn (1 = negate: acc' = sign(g) acc), bias (BW b),
//                     lo / hi (XW b, per-channel pre-clamp), m (MW b)
//       x = clamp(relu ? max(acc' + bias, 0) : acc' + bias, lo, hi)          (combinational, registered as XW b)
//   cycle n + 1 (late): sh (sel, SHW b; s' = SB + sel), h (16 b), sv (17 b: the stream entry read in place: r of a
//                     conv-shortcut block or s_in of an identity block), rmode, omode, t (TW b, T1 of the next block)
//       rs = rmode 0: 0 | 1: sv (r) | 2: relu(sv) (j = 0) | 3: (relu(sv) + 1) >> 1 (j = -1)     (registered, 17 b)
//   S1: P = x m, bits [SB - 1, SB - 1 + NP) registered
//   S2: q = P >>> (SB - 1 + sel), y = q >>> 1 (18 b, |y| < 2^17 contract), s = y + h + rs + q[0] (19 b)
//       omode 0 (sat): y_o = sat(s, +-32767), b_o = y_o > t;  1 (r): y_o = s (17 b, |s| < 2^16 contract), b_o = 0;
//       2 (u8): y_o = clamp(s, 0, 127), b_o = 0
//   outputs after edge n + 2 (latency 3, one output per cycle).  rst_n: synchronous, clears the valid pipeline only.

module qbf_reg #(parameter int W = 1) (input logic clk, input logic [W-1:0] d, output logic [W-1:0] q);
    always_ff @(posedge clk) q <= d;
endmodule

module qbf_pre #(parameter int AW = 20, BW = 16, XW = 16, PC = 1) (   // sign negate, bias pre-add, ReLU, pre-clamp
    input  logic signed [AW-1:0] acc,
    input  logic                 sgn, relu,
    input  logic signed [BW-1:0] bias,
    input  logic signed [XW-1:0] lo, hi,
    output logic signed [XW-1:0] x
);
    localparam int EW = (AW > BW ? AW : BW) + 2;
    always_comb begin
        logic signed [EW-1:0] a, xb;
`ifdef QBF_MUT_SGN
        a  = sgn ? ~EW'(acc) : EW'(acc);                        // mutant: one's complement negate
`else
        a  = sgn ? -EW'(acc) : EW'(acc);
`endif
        xb = a + EW'(bias);
        if (relu && xb < 0)     xb = '0;
`ifdef QBF_MUT_CLAMP
        if (0)                  x = lo;                         // mutant: no lower pre-clamp
`else
        if (PC != 0 && xb < EW'(lo))       x = lo;
`endif
        else if (PC != 0 && xb > EW'(hi))  x = hi;
        else                               x = XW'(xb);       // PC = 0: compiler contract, x' fits XW b
    end
endmodule

module qbf_res (                                                // p2 residual select (no multiplier)
    input  logic signed [16:0] sv,
    input  logic        [1:0]  rmode,
    output logic signed [16:0] rs
);
    always_comb begin
        logic [15:0] pr;                                        // relu(sv), sv <= 65535 never needed beyond 16 b
        pr = sv[16] ? 16'd0 : sv[15:0];
        case (rmode)
            2'd0: rs = '0;
            2'd1: rs = sv;
            2'd2: rs = {1'b0, pr};
`ifdef QBF_MUT_RND
            default: rs = 17'({1'b0, pr}) >>> 1;                   // mutant: j = -1 without round half up
`else
            default: rs = 17'({1'b0, pr} + 17'd1) >>> 1;
`endif
        endcase
    end
endmodule

module qbf_mul #(parameter int XW = 16, MW = 29) (
    input  logic signed [XW-1:0]    x,
    input  logic        [MW-1:0]    m,
    output logic signed [XW+MW-1:0] p
);
    assign p = x * $signed({1'b0, m});
endmodule

module qbf_fin #(parameter int NP = 29, SHW = 4, TW = 16) (
    input  logic signed [NP-1:0]   p,                           // P >>> (SB - 1)
    input  logic        [SHW-1:0]  sh,
    input  logic signed [15:0]     h,
    input  logic signed [16:0]     rs,
    input  logic        [1:0]      omode,
    input  logic signed [TW-1:0]   t,
    output logic signed [16:0]     y,
    output logic                   b
);
    localparam int CW = (TW > 16 ? TW : 16) + 1;
    always_comb begin
        logic signed [NP-1:0] q, yq;
        logic signed [17:0]   y18;
        logic signed [18:0]   s;
        logic signed [15:0]   ys;
        q   = p >>> sh;
        yq  = q >>> 1;
        y18 = 18'(yq);                                          // truncation: |y| < 2^17 contract
        s   = 19'(y18) + 19'(h) + 19'(rs) + 19'(q[0]);
        if      (s >  19'sd32767) ys = 16'sd32767;
        else if (s < -19'sd32767) ys = -16'sd32767;
        else                      ys = 16'(s);
        case (omode)
            2'd0:    y = 17'(ys);
            2'd1:    y = 17'(s);
            default: y = (s < 0) ? 17'd0 : (s > 19'sd127) ? 17'd127 : 17'(s);
        endcase
        b = (omode == 2'd0) && (CW'(ys) > CW'(t));
    end
endmodule

module qbf_lane #(
    parameter int AW = 20, BW = 16, XW = 16, MW = 29, TW = 16, SHW = 4, SB = 17, PC = 1
) (
    input  logic                 clk, rst_n, vld, relu,
    input  logic signed [AW-1:0] acc,                           // cycle n
    input  logic                 sgn,
    input  logic signed [BW-1:0] bias,
    input  logic signed [XW-1:0] lo, hi,
    input  logic        [MW-1:0] m,
    input  logic        [SHW-1:0] sh,                           // cycle n + 1
    input  logic signed [15:0]   h,
    input  logic signed [16:0]   sv,
    input  logic        [1:0]    rmode, omode,
    input  logic signed [TW-1:0] t,
    output logic                 vld_o,
    output logic signed [16:0]   y_o,
    output logic                 b_o
);
    localparam int PWD = XW + MW;
    localparam int YW = 18;
    localparam int NPT = (1 << SHW) - 1 + YW + 1;
    localparam int NP = NPT < PWD - SB + 1 ? NPT : PWD - SB + 1;
    // S0: pre-processing, input registers
    logic signed [XW-1:0] xp, x0;
    logic        [MW-1:0] m0;
    logic                 v0, v1;
    qbf_pre #(AW, BW, XW, PC) u_pre (.acc, .sgn, .relu, .bias, .lo, .hi, .x(xp));
    qbf_reg #(1 + XW + MW) u_rin (.clk, .d({rst_n & vld, xp, m}), .q({v0, x0, m0}));
    // late operands
    logic signed [16:0]   rsc, rs1;
    logic signed [15:0]   h1;
    logic signed [TW-1:0] t1;
    logic        [SHW-1:0] sh1;
    logic        [1:0]    om1;
    qbf_res u_res (.sv, .rmode, .rs(rsc));
    qbf_reg #(17 + 16 + TW + SHW + 2) u_rlate (.clk, .d({rsc, h, t, sh, omode}), .q({rs1, h1, t1, sh1, om1}));
    // S1: product
    logic signed [PWD-1:0] prod;
    logic signed [PWD:0]   prode;
    logic signed [NP-1:0]  p1;
    qbf_mul #(XW, MW) u_mul (.x(x0), .m(m0), .p(prod));
    assign prode = {prod[PWD-1], prod};
    qbf_reg #(NP + 1) u_rp1 (.clk, .d({rst_n & v0, NP'(prode >>> (SB - 1))}), .q({v1, p1}));
    // S2: window select, + h + rs + round, output modes, compare
    logic signed [16:0] yo;
    logic               bo;
    qbf_fin #(NP, SHW, TW) u_fin (.p(p1), .sh(sh1), .h(h1), .rs(rs1), .omode(om1), .t(t1), .y(yo), .b(bo));
    qbf_reg #(19) u_rout (.clk, .d({rst_n & v1, yo, bo}), .q({vld_o, y_o, b_o}));
endmodule

// synthesis tops (parameters from results/lane.md "qb_lane_f": MW / SHW measured on the p2 programs of E6_s0 / E6_s1):
//   qb_lane_f  SHW 4 (s' in [17, 32]: the E6_s0 p2 b6.hm needs s' = 29), qb_lane_f3  SHW 3 (qb_lane_s8 window, area ref.),
//   qb_lane_fn SHW 4 without the pre-clamp (lo / hi unused; exact for the p2 programs, whose fused-lane domains fit 16 b)
`ifndef QBF_MW
`define QBF_MW 28
`endif
`define QBF_TOP(NAME, SHW_, PC_) \
module NAME ( \
    input  logic clk, rst_n, vld, relu, \
    input  logic signed [19:0] acc, \
    input  logic sgn, \
    input  logic signed [15:0] bias, \
    input  logic signed [15:0] lo, hi, \
    input  logic        [`QBF_MW-1:0] m, \
    input  logic        [SHW_-1:0] sh, \
    input  logic signed [15:0] h, \
    input  logic signed [16:0] sv, \
    input  logic        [1:0]  rmode, omode, \
    input  logic signed [15:0] t, \
    output logic vld_o, \
    output logic signed [16:0] y_o, \
    output logic b_o \
); \
    qbf_lane #(.AW(20), .BW(16), .XW(16), .MW(`QBF_MW), .TW(16), .SHW(SHW_), .SB(17), .PC(PC_)) u_lane (.*); \
endmodule

`QBF_TOP(qb_lane_f, 4, 1)
`QBF_TOP(qb_lane_f3, 3, 1)
`QBF_TOP(qb_lane_fn, 4, 0)
