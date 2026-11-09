// Standalone ablation tops (qc18acc/ablation): the array behind the same input pipeline register for all three
// variants (as the v2 xbar S3 / code registers in front of qa_array): in_x (8 x 64 b), in_w (8 x WB b), vld / first /
// last / shift (synchronous active-low reset, as the v2 control registers).  Heads are the shadow-register outputs.
//   qab_top_qc    V = 0: qa_array / qa_pe of qc18acc/hw/rtl, UNCHANGED (WB = 10 code bits, ACC = qa_pkg::ACC = 20)
//   qab_top_tern  V = 1: qab_array, 64 trits per block (WB = 128), ACC 21 (worst case of an arbitrary ternary
//                 3x3x512 conv: 4608 x 128 = 589 824 < 2^20)
//   qab_top_int8  V = 2: qab_array, 64 int8 per block (WB = 512), ACC 32
module qab_wrap #(parameter int V = 0, parameter int WB = 10, parameter int ACC = 20) (
  input  logic               clk, rst_n,
  input  logic               in_vld, in_first, in_last,
  input  logic [7:0]         in_shift,
  input  logic [511:0]       in_x,
  input  logic [8*WB-1:0]    in_w,
  output logic [64*ACC-1:0]  heads
);
  logic vld, first, last;
  logic [7:0] shift;
  logic [511:0] x;
  logic [8*WB-1:0] w;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      vld <= 1'b0; first <= 1'b0; last <= 1'b0; shift <= '0;
    end else begin
      vld <= in_vld; first <= in_first; last <= in_last; shift <= in_shift;
    end
    x <= in_x;
    w <= in_w;
  end
  if (V == 0) begin : g_qc
    qa_array u_array (.clk(clk), .vld(vld), .first(first), .last(last), .x(x), .code(w), .shift(shift), .heads(heads));
  end else begin : g_d
    qab_array #(.V(V), .WB(WB), .ACC(ACC)) u_array (.clk(clk), .vld(vld), .first(first), .last(last), .x(x), .w(w),
      .shift(shift), .heads(heads));
  end
endmodule

module qab_top_qc (
  input logic clk, rst_n, in_vld, in_first, in_last, input logic [7:0] in_shift, input logic [511:0] in_x,
  input logic [79:0] in_w, output logic [1279:0] heads);
  qab_wrap #(.V(0), .WB(10), .ACC(20)) u_wrap (.*);
endmodule

module qab_top_tern (
  input logic clk, rst_n, in_vld, in_first, in_last, input logic [7:0] in_shift, input logic [511:0] in_x,
  input logic [1023:0] in_w, output logic [1343:0] heads);
  qab_wrap #(.V(1), .WB(128), .ACC(21)) u_wrap (.*);
endmodule

module qab_top_int8 (
  input logic clk, rst_n, in_vld, in_first, in_last, input logic [7:0] in_shift, input logic [511:0] in_x,
  input logic [4095:0] in_w, output logic [2047:0] heads);
  qab_wrap #(.V(2), .WB(512), .ACC(32)) u_wrap (.*);
endmodule
