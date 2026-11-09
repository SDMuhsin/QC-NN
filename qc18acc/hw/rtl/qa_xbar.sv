// S2 -> S3: kw window, act-buffer crossbar and code register (v2).
// Window W[8] (S3 registers, raw 64-b words, never masked): slot j holds the input word of index B + j of the current
// step (qa_agu).  On a step (s2_vld): a shift step first moves slot j + 1 to slot j, then every slot j with rd[j]
// is loaded from bank (rot + j) mod 8 (registered macro outputs); slots neither held nor read are don't-care (their
// lanes are padding).  Row p (tile pixel o0 + p) = W[p] if lane p is valid, else zero: the padding mask is a
// registered 8-b lane mask ANDed at the array input, so a raw word of an out-of-map index can sit in the window but
// never reaches a PE.  Column g takes the 10-b code at bits [10g+9 : 10g] of the weight word (S3 code register).
module qa_xbar import qa_pkg::*; (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 s1_vld, s1_first, s1_last,
  input  logic [2:0]           s1_rot,
  input  logic [7:0]           s1_lane,
  input  logic [7:0]           s1_rd,
  input  logic                 s1_shift,
  input  logic [NBANK*64-1:0]  ar_rdata,     // S2: bank k data
  input  logic [WBITS-1:0]     w_rdata,      // S2: weight word
  output logic                 s3_vld, s3_first, s3_last,
  output logic [8*64-1:0]      s3_x,         // row p activation word (masked)
  output logic [8*10-1:0]      s3_code       // column g code
);
  logic       s2_vld, s2_first, s2_last, s2_shift;
  logic [2:0] s2_rot;
  logic [7:0] s2_lane, s2_rd, s3_lane;
  logic [8*64-1:0] win;
  wire  [8*64-1:0] win_sh = {64'd0, win[8*64-1:64]};      // slot j <- slot j + 1
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s2_vld <= 1'b0; s3_vld <= 1'b0; s2_first <= 1'b0; s2_last <= 1'b0; s3_first <= 1'b0; s3_last <= 1'b0;
    end else begin
      s2_vld <= s1_vld; s3_vld <= s2_vld;
      s2_first <= s1_first; s2_last <= s1_last; s3_first <= s2_first; s3_last <= s2_last;
    end
  end
  always_ff @(posedge clk) begin
    if (s1_vld) begin s2_rot <= s1_rot; s2_lane <= s1_lane; s2_rd <= s1_rd; s2_shift <= s1_shift; end
    if (s2_vld) begin
      for (int j = 0; j < 8; j++)
        if (s2_rd[j]) win[j*64 +: 64] <= ar_rdata[3'(j + s2_rot)*64 +: 64];
        else if (s2_shift) win[j*64 +: 64] <= win_sh[j*64 +: 64];
      s3_lane <= s2_lane;
      s3_code <= w_rdata[79:0];
    end
  end
  always_comb
    for (int p = 0; p < 8; p++) s3_x[p*64 +: 64] = s3_lane[p] ? win[p*64 +: 64] : 64'd0;
endmodule
