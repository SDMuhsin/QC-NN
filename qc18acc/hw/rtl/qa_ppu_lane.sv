// One PPU lane (ARCH "PPU"); pipeline registers r1..r6, rN loads when stage N-1 holds a valid word (eN).
//   r1  inputs: acc, bias, m0, sh, d
//   r2  v = (d ? -acc : acc) + bias                                   (int32)
//   r3  partial products v * m0[15:0], v * m0[30:16]                  (32 x 31 multiply, 2 stages)
//   r4  s = pp_lo + (pp_hi << 16) + 2^(sh-1)                           (64 b)
//   r5  y = sat20(s >>> sh)          residual term: RES_ID sat20((q * idm0 + 2^(idsh-1)) >>> idsh), RES_R int16
//   r6  RELU / head: clamp(y, 0, 127); RES_*: clamp(y + res, 0, 127); RAW16: y[7:0] (+ y[15:8] for the hi plane)
// Residual bytes: q / R low byte arrive (registered macro output) in the r2 cycle, the R high byte in the r3 cycle.
module qa_ppu_lane import qa_pkg::*; (
  input  logic              clk,
  input  logic              e1, e2, e3, e4, e5, e6,
  input  logic [1:0]        mode,           // pass mode (head: RELU)
  input  logic [ACC-1:0]    acc,
  input  logic [31:0]       bias,
  input  logic [30:0]       m0,
  input  logic [5:0]        sh,
  input  logic              d,
  input  logic [7:0]        rlo,            // residual byte (r2 cycle)
  input  logic [7:0]        rhi,            // R high byte (r3 cycle)
  input  logic [30:0]       idm0,
  input  logic [5:0]        idsh,
  output logic [7:0]        out6,
  output logic [7:0]        out6_hi
);
  localparam logic signed [YW-1:0] YMAX = {1'b0, {(YW-1){1'b1}}}, YMIN = {1'b1, {(YW-1){1'b0}}};
  logic signed [ACC-1:0] acc1;
  logic signed [31:0]    bias1, v2;
  logic [30:0]           m01, m02;
  logic [5:0]            sh1, sh2, sh3, sh4;
  logic                  d1;
  logic signed [47:0]    pplo3, pphi3;
  logic signed [63:0]    s4;
  logic signed [39:0]    qm4;
  logic [7:0]            lo3, rlo3;
  logic signed [15:0]    r16_4;
  logic signed [YW-1:0]  y5, res5;

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

  logic signed [31:0] acc32;
  logic signed [63:0] ysh, qsh;
  logic signed [YW:0] sum5;
  always_comb begin
    acc32 = acc1;                                           // sign-extend
    ysh = s4 >>> sh4;
    qsh = (qm4 + rnd(idsh)) >>> idsh;
    sum5 = y5;
    if (mode == M_RES_ID || mode == M_RES_R) sum5 = y5 + res5;
  end

  always_ff @(posedge clk) begin
    if (e1) begin acc1 <= acc; bias1 <= bias; m01 <= m0; sh1 <= sh; d1 <= d; end
    if (e2) begin v2 <= (d1 ? -acc32 : acc32) + bias1; m02 <= m01; sh2 <= sh1; end
    if (e3) begin
      pplo3 <= v2 * $signed({1'b0, m02[15:0]});
      pphi3 <= v2 * $signed({1'b0, m02[30:16]});
      sh3 <= sh2;
      rlo3 <= rlo;
    end
    if (e4) begin
      s4 <= pplo3 + (pphi3 <<< 16) + rnd(sh3);
      sh4 <= sh3;
      qm4 <= $signed(rlo3) * $signed({1'b0, idm0});
      r16_4 <= $signed({rhi, rlo3});
    end
    if (e5) begin
      y5 <= sat(ysh);
      res5 <= (mode == M_RES_ID) ? sat(qsh) : r16_4;
    end
    if (e6) begin
      out6 <= (mode == M_RAW16) ? y5[7:0] : clamp(sum5);
      out6_hi <= y5[15:8];
    end
  end
`ifndef SYNTHESIS
  always @(posedge clk) if (e5 === 1'b1) begin
    if (mode == M_RAW16 && (ysh > 32767 || ysh < -32768)) $error("qa_ppu_lane: RAW16 value %0d outside int16", ysh);
    if (mode == M_RES_ID && (qsh > YMAX || qsh < YMIN)) $error("qa_ppu_lane: RES_ID term %0d saturated", qsh);
  end
  always @(posedge clk) if (e4 === 1'b1 && sh3 == 0) $error("qa_ppu_lane: sh = 0");
`endif
endmodule
