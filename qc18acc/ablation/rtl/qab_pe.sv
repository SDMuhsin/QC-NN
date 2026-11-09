// Ablation PEs of the QC18-ACC array (qc18acc/ablation): same interface, registers and control as the v2 qa_pe
// (one 8x8 block per cycle, output-stationary, first step of a tile overwrites, last step captures into the shadow
// register, shadow shifts along the column chain), only the block arithmetic and the widths differ.
//   TERNARY  w = 64 trits (2 b, lane i input j at bits [2(8i+j)+1 : 2(8i+j)]; 01 = +1, 11 = -1, 00 / 10 = 0, the qa_pe
//            trit code): y[i] = sum_j trit_ij x[j]  (8 trit-selects + adder tree -> 12 b), accumulator ACC = 21 b.
//   INT8     w = 64 int8 (lane i input j at bits [8(8i+j)+7 : 8(8i+j)]): y[i] = sum_j w_ij x[j]  (8 signed 8x8
//            multipliers + adder tree -> 19 b), accumulator ACC = 32 b.
// Sub-instances as in the v2 PE: u_dot (block arithmetic, = qa_pe rot + tadd) and u_acc (accumulate add).
module qab_pe #(parameter int V = 1, parameter int WB = 128, parameter int ACC = 21) (
  input  logic              clk,
  input  logic              vld, first, last,
  input  logic [63:0]       x,
  input  logic [WB-1:0]     w,
  input  logic              shift,
  input  logic [8*ACC-1:0]  sh_in,
  output logic [8*ACC-1:0]  sh_out
);
  localparam int SW = (V == 1) ? 12 : 19;
  logic [8*ACC-1:0] acc_q, sum;
  logic [8*SW-1:0] s;
  if (V == 1) begin : g_t
    qab_dot_tern u_dot (.x(x), .w(w), .s(s));
  end else begin : g_i
    qab_dot_int8 u_dot (.x(x), .w(w), .s(s));
  end
  qab_acc #(.ACC(ACC), .SW(SW)) u_acc (.first(first), .acc(acc_q), .s(s), .sum(sum));
  always_ff @(posedge clk) begin
    if (vld && !last) acc_q <= sum;
    if (vld && last) sh_out <= sum;
    else if (shift) sh_out <= sh_in;
  end
endmodule

// s lane i = sum_j trit(w_ij) x_j, 12 b signed (|s| <= 8 * 128)
module qab_dot_tern (
  input  logic [63:0]    x,
  input  logic [127:0]   w,
  output logic [8*12-1:0] s
);
  function automatic logic signed [11:0] trit(input logic [7:0] v, input logic [1:0] t);
    case (t)
      2'b01:   trit = 12'($signed(v));
      2'b11:   trit = -12'($signed(v));
      default: trit = 12'sd0;
    endcase
  endfunction
  always_comb
    for (int i = 0; i < 8; i++) begin
      logic signed [11:0] a;
      a = '0;
      for (int j = 0; j < 8; j++) a = a + trit(x[j*8 +: 8], w[(i*8+j)*2 +: 2]);
      s[i*12 +: 12] = a;
    end
endmodule

// s lane i = sum_j w_ij x_j, 19 b signed (|s| <= 8 * 128 * 128)
module qab_dot_int8 (
  input  logic [63:0]    x,
  input  logic [511:0]   w,
  output logic [8*19-1:0] s
);
  always_comb
    for (int i = 0; i < 8; i++) begin
      logic signed [18:0] a;
      a = '0;
      for (int j = 0; j < 8; j++) a = a + 19'($signed(x[j*8 +: 8]) * $signed(w[(i*8+j)*8 +: 8]));
      s[i*19 +: 19] = a;
    end
endmodule

// sum lane i = (first ? 0 : acc_i) + s_i   (as qa_pe_acc, parameterised widths)
module qab_acc #(parameter int ACC = 21, parameter int SW = 12) (
  input  logic              first,
  input  logic [8*ACC-1:0]  acc,
  input  logic [8*SW-1:0]   s,
  output logic [8*ACC-1:0]  sum
);
  always_comb
    for (int i = 0; i < 8; i++)
      sum[i*ACC +: ACC] = (first ? '0 : $signed(acc[i*ACC +: ACC])) + ACC'($signed(s[i*SW +: SW]));
endmodule
