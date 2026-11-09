// QC block PE: one 8x8 block per cycle, output-stationary.  y[i] = t1 x[(i+k1) mod 8] + t2 x[(i+k2) mod 8]
// (code bits [4:0] = {k1, t1}, [9:5] = {k2, t2}; trit 01 = +1, 11 = -1, 00 / 10 = 0), accumulated into 8 x 20-b
// accumulators (first step of a tile overwrites).  The last step of a tile writes the sum into the shadow register
// instead (capture, 1 cycle); the shadow shifts along the column chain (towards p = 0) when the drain controller pops
// the column head.
// v2: the function groups are sub-instances (for the per-function power / area breakdown; same arithmetic):
//   u_rot1 / u_rot2  qa_pe_rot   8-lane rotator (3-level 8-b mux) by k1 / k2
//   u_tadd           qa_pe_tadd  trit apply (negate / zero) + 2-term add per lane -> 10 b
//   u_acc            qa_pe_acc   accumulator add per lane: (first ? 0 : acc) + 2-term sum -> 20 b
//   acc_q, sh_out    registers in qa_pe (accumulators; shadow with its capture / shift-in mux)
module qa_pe import qa_pkg::*; (
  input  logic              clk,
  input  logic              vld, first, last,
  input  logic [63:0]       x,
  input  logic [9:0]        code,
  input  logic              shift,
  input  logic [8*ACC-1:0]  sh_in,
  output logic [8*ACC-1:0]  sh_out
);
  logic [8*ACC-1:0] acc_q, sum;
  logic [63:0] xr1, xr2;
  logic [8*10-1:0] ts;
  qa_pe_rot  u_rot1 (.x(x), .k(code[4:2]), .y(xr1));
  qa_pe_rot  u_rot2 (.x(x), .k(code[9:7]), .y(xr2));
  qa_pe_tadd u_tadd (.a(xr1), .b(xr2), .t1(code[1:0]), .t2(code[6:5]), .s(ts));
  qa_pe_acc  u_acc  (.first(first), .acc(acc_q), .s(ts), .sum(sum));
  always_ff @(posedge clk) begin
    if (vld && !last) acc_q <= sum;
    if (vld && last) sh_out <= sum;
    else if (shift) sh_out <= sh_in;
  end
endmodule

// y lane i = x lane (i + k) mod 8
module qa_pe_rot (
  input  logic [63:0] x,
  input  logic [2:0]  k,
  output logic [63:0] y
);
  always_comb for (int i = 0; i < 8; i++) y[i*8 +: 8] = x[3'(i + k)*8 +: 8];
endmodule

// s lane i = trit(a_i, t1) + trit(b_i, t2), 10 b signed
module qa_pe_tadd (
  input  logic [63:0]   a, b,
  input  logic [1:0]    t1, t2,
  output logic [8*10-1:0] s
);
  function automatic logic signed [9:0] trit(input logic [7:0] v, input logic [1:0] t);
    case (t)
      2'b01:   trit = $signed({{2{v[7]}}, v});
      2'b11:   trit = -$signed({{2{v[7]}}, v});
      default: trit = 10'sd0;
    endcase
  endfunction
  always_comb for (int i = 0; i < 8; i++) s[i*10 +: 10] = trit(a[i*8 +: 8], t1) + trit(b[i*8 +: 8], t2);
endmodule

// sum lane i = (first ? 0 : acc_i) + s_i
module qa_pe_acc import qa_pkg::*; (
  input  logic              first,
  input  logic [8*ACC-1:0]  acc,
  input  logic [8*10-1:0]   s,
  output logic [8*ACC-1:0]  sum
);
  always_comb
    for (int i = 0; i < 8; i++)
      sum[i*ACC +: ACC] = (first ? '0 : $signed(acc[i*ACC +: ACC])) + ACC'($signed(s[i*10 +: 10]));
endmodule
