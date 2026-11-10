// One v4 PPU lane: v3 qa_ppu_lane (hw3/rtl, 20-b v, 20 x 31 multiply in 2 partial products) re-timed for the v4
// residual port latency (RLAT = 5: a residual word requested at the drain read D0 arrives in cycle D0 + 5, the RES_R
// high-byte word in D0 + 6).  Register stages (en_k captures at the end of cycle D0 + k - 1):
//   r1  inputs: acc, bias (20 b), m0, sh, d
//   r2  v = (d ? -acc : acc) + bias                                   (20 b)
//   r3  partial products v * m0[15:0], v * m0[30:16]
//   r4  s = pp_lo + (pp_hi << 16) + 2^(sh-1)                           (64 b)
//   r5  y = sat20(s >>> sh)
//   r6  y; residual q (or R low byte) * idm0 (RES_ID), R low byte      (residual word of D0 + 5)
//   r7  y; residual term: RES_ID sat20((q * idm0 + 2^(idsh-1)) >>> idsh), RES_R int16 {R high byte (D0 + 6), low}
//   r8  RELU / head: clamp(y, 0, 127); RES_*: clamp(y + res, 0, 127); RAW16: y[7:0] (+ y[15:8] for the high plane)
module qa_ppu_lane import qa_pkg::*; (
  input  logic              clk,
  input  logic [8:1]        en,
  input  logic [1:0]        mode,
  input  logic [ACC-1:0]    acc,
  input  logic [VW-1:0]     bias,
  input  logic [30:0]       m0,
  input  logic [5:0]        sh,
  input  logic              d,
  input  logic [7:0]        rdat,          // residual byte of this lane in the current cycle
  input  logic [30:0]       idm0,
  input  logic [5:0]        idsh,
  output logic [7:0]        out8,
  output logic [7:0]        out8_hi
);
  localparam logic signed [YW-1:0] YMAX = {1'b0, {(YW-1){1'b1}}}, YMIN = {1'b1, {(YW-1){1'b0}}};
  logic signed [ACC-1:0] acc1;
  logic signed [VW-1:0]  bias1, v2;
  logic [30:0]           m01, m02;
  logic [5:0]            sh1, sh2, sh3, sh4;
  logic                  d1;
  logic signed [VW+16:0] pplo3, pphi3;
  logic signed [63:0]    s4;
  logic signed [YW-1:0]  y5, y6, y7, res7;
  logic signed [39:0]    qm6;
  logic [7:0]            rlo6;

  function automatic logic signed [YW-1:0] sat(input logic signed [63:0] x);
    if (x > YMAX) sat = YMAX;
    else if (x < YMIN) sat = YMIN;
    else sat = YW'(x);
  endfunction
  function automatic logic signed [63:0] rnd(input logic [5:0] s);
    rnd = (s == 0) ? 64'sd0 : (64'sd1 <<< (s - 6'd1));
  endfunction
  function automatic logic [7:0] clamp(input logic signed [YW:0] x);
    clamp = x < 0 ? 8'd0 : (x > 127 ? 8'd127 : 8'(x));
  endfunction

  logic signed [VW:0]  v_full;
  logic signed [63:0]  ysh, qsh;
  logic signed [YW:0]  sum7;
  always_comb begin
    v_full = (d1 ? -(VW+1)'(acc1) : (VW+1)'(acc1)) + (VW+1)'(bias1);
    ysh = s4 >>> sh4;
    qsh = (qm6 + rnd(idsh)) >>> idsh;
    sum7 = y7;
    if (mode == M_RES_ID || mode == M_RES_R) sum7 = y7 + res7;
  end

  always_ff @(posedge clk) begin
    if (en[1]) begin acc1 <= acc; bias1 <= bias; m01 <= m0; sh1 <= sh; d1 <= d; end
    if (en[2]) begin v2 <= VW'(v_full); m02 <= m01; sh2 <= sh1; end
    if (en[3]) begin
      pplo3 <= v2 * $signed({1'b0, m02[15:0]});
      pphi3 <= v2 * $signed({1'b0, m02[30:16]});
      sh3 <= sh2;
    end
    if (en[4]) begin s4 <= 64'(pplo3) + (64'(pphi3) <<< 16) + rnd(sh3); sh4 <= sh3; end
    if (en[5]) y5 <= sat(ysh);
    if (en[6]) begin
      y6 <= y5;
      rlo6 <= rdat;
      qm6 <= $signed(rdat) * $signed({1'b0, idm0});
    end
    if (en[7]) begin
      y7 <= y6;
      res7 <= (mode == M_RES_ID) ? sat(qsh) : $signed({{(YW-16){rdat[7]}}, rdat, rlo6});
    end
    if (en[8]) begin
      out8 <= (mode == M_RAW16) ? y7[7:0] : clamp(sum7);
      out8_hi <= y7[15:8];
    end
  end
`ifndef SYNTHESIS
  always @(posedge clk) if (en[2] === 1'b1 && (v_full > $signed((VW+1)'(YMAX)) || v_full < $signed((VW+1)'(YMIN))))
    $error("qa_ppu_lane: v = %0d does not fit %0d b", v_full, VW);
  always @(posedge clk) if (en[5] === 1'b1 && mode == M_RAW16 && (ysh > 32767 || ysh < -32768))
    $error("qa_ppu_lane: RAW16 value %0d outside int16", ysh);
  always @(posedge clk) if (en[7] === 1'b1 && mode == M_RES_ID && (qsh > YMAX || qsh < YMIN))
    $error("qa_ppu_lane: RES_ID term %0d saturated", qsh);
  always @(posedge clk) if (en[4] === 1'b1 && sh3 == 0) $error("qa_ppu_lane: sh = 0");
`endif
endmodule
