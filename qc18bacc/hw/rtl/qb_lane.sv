// qb_lane: one PPU lane of the 1-bit-activation QC accelerator, one output per cycle, fully pipelined.
//   mode 0:  y = (x * m + 2^(sh-1)) >>> sh     (x signed XW, m unsigned MW, sh 6 b, sh >= 1; exact, any sh)
//            y_sat = sat(y + h + r, [-32767, 32767])   (h, r signed 16 b; no intermediate rounding / saturation)
//            b = (y_sat > T)                        (T signed TW)
//   mode 1:  b = (x >= T)     (compare-only; y_sat = 0)
// Implementation: (P + 2^(sh-1)) >> sh == ((P >>> (sh-1)) + 1) >>> 1 (no wide rounding constant); y is clamped to
// 18 b before + (h + r) (|h + r| < 2^17, so a clamped y saturates the same way).
// Pipeline (all inputs aligned with x): S0 input regs -> S1 product P, h + r, x >= T -> S2 shift / round / clamp
// -> S3 + (h + r), saturate, compare = output regs.  Latency 4 (input of cycle n at the outputs after edge n+3).
// rst_n: synchronous, clears the valid pipeline only.
module qb_lane #(
    parameter int XW = 16,
    parameter int MW = 27,
    parameter int TW = 17
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 vld,
    input  logic                 mode,
    input  logic signed [XW-1:0] x,
    input  logic        [MW-1:0] m,
    input  logic        [5:0]    sh,
    input  logic signed [15:0]   h,
    input  logic signed [15:0]   r,
    input  logic signed [TW-1:0] t,
    output logic                 vld_o,
    output logic signed [15:0]   y_o,
    output logic                 b_o
);
    localparam int PWD = XW + MW;   // |x * m| < 2^(PWD-1)

    // ---- S0
    logic                 v0, md0;
    logic signed [XW-1:0] x0;
    logic        [MW-1:0] m0;
    logic        [5:0]    sh0;
    logic signed [15:0]   h0, r0;
    logic signed [TW-1:0] t0;
    always_ff @(posedge clk) begin
        md0 <= mode; x0 <= x; m0 <= m; sh0 <= sh; h0 <= h; r0 <= r; t0 <= t;
        v0 <= rst_n ? vld : 1'b0;
    end

    // ---- S1: multiply
    logic                  v1, md1, c1;
    logic signed [PWD-1:0] p1;
    logic        [5:0]     sh1;
    logic signed [16:0]    hr1;
    logic signed [TW-1:0]  t1;
    logic signed [PWD-1:0] prod;
    assign prod = x0 * $signed({1'b0, m0});   // context width PWD: exact (|x * m| < 2^(PWD-1))
    always_ff @(posedge clk) begin
        p1  <= prod;
        hr1 <= 17'(h0) + 17'(r0);
        c1  <= (TW+1)'(x0) >= (TW+1)'(t0);
        md1 <= md0; sh1 <= sh0; t1 <= t0;
        v1  <= rst_n ? v0 : 1'b0;
    end

    // ---- S2: round-shift, clamp to 18 b
    logic                  v2, md2, c2;
    logic signed [17:0]    y2;
    logic signed [16:0]    hr2;
    logic signed [TW-1:0]  t2;
    always_ff @(posedge clk) begin
        logic signed [PWD-1:0] q;
        logic signed [PWD:0]   y;
        q = p1 >>> (sh1 - 6'd1);
        y = ((PWD+1)'(q) + (PWD+1)'(1)) >>> 1;
        if      (y > (PWD+1)'(131071))  y2 <= 18'sd131071;
        else if (y < -(PWD+1)'(131072)) y2 <= -18'sd131072;
        else                            y2 <= 18'(y);
        hr2 <= hr1; md2 <= md1; c2 <= c1; t2 <= t1;
        v2  <= rst_n ? v1 : 1'b0;
    end

    // ---- S3: + (h + r), saturate, compare
    always_ff @(posedge clk) begin
        logic signed [18:0] s;
        logic signed [15:0] ys;
        s = 19'(y2) + 19'(hr2);
        if      (s >  19'sd32767) ys = 16'sd32767;
        else if (s < -19'sd32767) ys = -16'sd32767;
        else                      ys = 16'(s);
        y_o   <= md2 ? 16'sd0 : ys;
        b_o   <= md2 ? c2 : ((TW+1)'(ys) > (TW+1)'(t2));
        vld_o <= rst_n ? v2 : 1'b0;
    end
endmodule

module qb_lane_n (
    input  logic                clk, rst_n, vld, mode,
    input  logic signed [15:0]  x,
    input  logic        [26:0]  m,
    input  logic        [5:0]   sh,
    input  logic signed [15:0]  h, r,
    input  logic signed [16:0]  t,
    output logic                vld_o,
    output logic signed [15:0]  y_o,
    output logic                b_o
);
    qb_lane #(.XW(16), .MW(27), .TW(17)) u_lane (.*);
endmodule

module qb_lane_w (
    input  logic                clk, rst_n, vld, mode,
    input  logic signed [19:0]  x,
    input  logic        [30:0]  m,
    input  logic        [5:0]   sh,
    input  logic signed [15:0]  h, r,
    input  logic signed [20:0]  t,
    output logic                vld_o,
    output logic signed [15:0]  y_o,
    output logic                b_o
);
    qb_lane #(.XW(20), .MW(31), .TW(21)) u_lane (.*);
endmodule
