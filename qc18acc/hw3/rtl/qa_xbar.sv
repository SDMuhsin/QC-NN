// v3 S2 -> S3: kw window on 128-b pair words, act-buffer crossbar and code register (v2 qa_xbar with 128-b slots).
// Window W[8] (S3 registers, raw pair words, never masked): slot j holds the input word of index B + j of the current
// step (qa_agu).  A shift step first moves slot j + 1 to slot j, then every slot j with rd[j] is loaded from bank
// (rot + j) mod 8.  Row p = W[p] if lane p is valid, else zero (registered lane mask at the array input).  Column g
// takes {odd code, even code} = bits [10g+9 : 10g] of the odd / even weight words (both read at the same address).
module qa_xbar import qa_pkg::*; (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 s1_vld, s1_first, s1_last,
  input  logic [2:0]           s1_rot,
  input  logic [7:0]           s1_lane,
  input  logic [7:0]           s1_rd,
  input  logic                 s1_shift,
  input  logic [NBANK*128-1:0] ar_rdata,     // S2: bank k pair word
  input  logic [WBITS-1:0]     we_rdata,     // S2: even weight word
  input  logic [WBITS-1:0]     wo_rdata,     // S2: odd weight word
  output logic                 s3_vld, s3_first, s3_last,
  output logic [8*128-1:0]     s3_x,
  output logic [8*20-1:0]      s3_code
);
  logic       s2_vld, s2_first, s2_last, s2_shift;
  logic [2:0] s2_rot;
  logic [7:0] s2_lane, s2_rd, s3_lane;
  logic [8*128-1:0] win;
  wire  [8*128-1:0] win_sh = {128'd0, win[8*128-1:128]};
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
        if (s2_rd[j]) win[j*128 +: 128] <= ar_rdata[3'(j + s2_rot)*128 +: 128];
        else if (s2_shift) win[j*128 +: 128] <= win_sh[j*128 +: 128];
      s3_lane <= s2_lane;
      for (int g = 0; g < 8; g++) s3_code[g*20 +: 20] <= {wo_rdata[g*10 +: 10], we_rdata[g*10 +: 10]};
    end
  end
  always_comb
    for (int p = 0; p < 8; p++) s3_x[p*128 +: 128] = s3_lane[p] ? win[p*128 +: 128] : 128'd0;
endmodule
