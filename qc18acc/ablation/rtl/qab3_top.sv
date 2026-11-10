// Standalone ablation tops at Kb = 2 (qc18acc/ablation, v3 geometry): the array behind the same input pipeline
// register for all three variants (qab_top.sv with the v3 widths): in_x (8 x 128 b), in_w (8 x WB b), vld / first /
// last / shift.  Heads are the shadow-register outputs.
//   qab3_top_qc    V = 0: qa_array / qa_pe of qc18acc/hw3/rtl, UNCHANGED (WB = 20 code bits, ACC = qa_pkg::ACC = 20)
//   qab3_top_tern  V = 1: qab3_array, 2 x 64 trits per column (WB = 256), ACC 21
//   qab3_top_int8  V = 2: qab3_array, 2 x 64 int8 per column (WB = 1024), ACC 32
module qab3_wrap #(parameter int V = 0, parameter int WB = 20, parameter int ACC = 20) (
  input  logic               clk, rst_n,
  input  logic               in_vld, in_first, in_last,
  input  logic [7:0]         in_shift,
  input  logic [1023:0]      in_x,
  input  logic [8*WB-1:0]    in_w,
  output logic [64*ACC-1:0]  heads
);
  logic vld, first, last;
  logic [7:0] shift;
  logic [1023:0] x;
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
    qab3_array #(.V(V), .WB(WB), .ACC(ACC)) u_array (.clk(clk), .vld(vld), .first(first), .last(last), .x(x), .w(w),
      .shift(shift), .heads(heads));
  end
endmodule

module qab3_top_qc (
  input logic clk, rst_n, in_vld, in_first, in_last, input logic [7:0] in_shift, input logic [1023:0] in_x,
  input logic [159:0] in_w, output logic [1279:0] heads);
  qab3_wrap #(.V(0), .WB(20), .ACC(20)) u_wrap (.*);
endmodule

module qab3_top_tern (
  input logic clk, rst_n, in_vld, in_first, in_last, input logic [7:0] in_shift, input logic [1023:0] in_x,
  input logic [2047:0] in_w, output logic [1343:0] heads);
  qab3_wrap #(.V(1), .WB(256), .ACC(21)) u_wrap (.*);
endmodule

module qab3_top_int8 (
  input logic clk, rst_n, in_vld, in_first, in_last, input logic [7:0] in_shift, input logic [1023:0] in_x,
  input logic [8191:0] in_w, output logic [2047:0] heads);
  qab3_wrap #(.V(2), .WB(1024), .ACC(32)) u_wrap (.*);
endmodule
