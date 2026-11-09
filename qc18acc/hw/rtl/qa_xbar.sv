// S2 -> S3: act-buffer crossbar and code register.  Row p (tile pixel o0 + p) takes bank (p + rot) mod 8 of the
// input buffer (registered macro outputs), zero if the lane is padding; column g takes the 10-b code at bits
// [10g+9 : 10g] of the weight word.  Everything lands in the S3 registers that feed the PE array.
module qa_xbar import qa_pkg::*; (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 s1_vld, s1_first, s1_last,
  input  logic [2:0]           s1_rot,
  input  logic [7:0]           s1_lane,
  input  logic [NBANK*64-1:0]  ar_rdata,     // S2: bank k data
  input  logic [WBITS-1:0]     w_rdata,      // S2: weight word
  output logic                 s3_vld, s3_first, s3_last,
  output logic [8*64-1:0]      s3_x,         // row p activation word
  output logic [8*10-1:0]      s3_code       // column g code
);
  logic       s2_vld, s2_first, s2_last;
  logic [2:0] s2_rot;
  logic [7:0] s2_lane;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s2_vld <= 1'b0; s3_vld <= 1'b0; s2_first <= 1'b0; s2_last <= 1'b0; s3_first <= 1'b0; s3_last <= 1'b0;
    end else begin
      s2_vld <= s1_vld; s3_vld <= s2_vld;
      s2_first <= s1_first; s2_last <= s1_last; s3_first <= s2_first; s3_last <= s2_last;
    end
  end
  always_ff @(posedge clk) begin
    if (s1_vld) begin s2_rot <= s1_rot; s2_lane <= s1_lane; end
    if (s2_vld) begin
      for (int p = 0; p < 8; p++)
        s3_x[p*64 +: 64] <= s2_lane[p] ? ar_rdata[3'(p + s2_rot)*64 +: 64] : 64'd0;
      s3_code <= w_rdata[79:0];
    end
  end
endmodule
