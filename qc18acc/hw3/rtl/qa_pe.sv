// v3 QC block PE: TWO 8x8 blocks per cycle (Kb = 2), output-stationary.  Row input x = one 128-b pair word: x[63:0]
// = input group 2j (even block), x[127:64] = group 2j + 1 (odd block); code[9:0] = even block, code[19:10] = odd
// block, each {k2, t2, k1, t1} as v2 (trit 01 = +1, 11 = -1, 00 / 10 = 0).  Per lane i:
//   acc_i <= (first ? 0 : acc_i) + t1e x_e[(i+k1e)%8] + t2e x_e[(i+k2e)%8] + t1o x_o[(i+k1o)%8] + t2o x_o[(i+k2o)%8]
// as ONE combinational sum in one module (u_acc, qa_pe_acc4: trit apply + 4 terms + accumulate, no hierarchy split
// between the term adds and the accumulate; ARCH "v3").  The last step of a tile writes the sum into the shadow
// register instead (capture), which shifts along the column chain (towards p = 0) when the drain pops the head.
//   u_rot1..u_rot4  qa_pe_rot   8-lane rotators (3-level 8-b mux): even k1 / k2, odd k1 / k2
//   u_acc           qa_pe_acc4  fused trits + 4-term + accumulate add -> 20 b
//   acc_q, sh_out   registers in qa_pe (accumulators; shadow with its capture / shift-in mux)
module qa_pe import qa_pkg::*; (
  input  logic              clk,
  input  logic              vld, first, last,
  input  logic [127:0]      x,
  input  logic [19:0]       code,
  input  logic              shift,
  input  logic [8*ACC-1:0]  sh_in,
  output logic [8*ACC-1:0]  sh_out
);
  logic [8*ACC-1:0] acc_q, sum;
  logic [63:0] r1, r2, r3, r4;
  qa_pe_rot  u_rot1 (.x(x[63:0]),   .k(code[4:2]),   .y(r1));
  qa_pe_rot  u_rot2 (.x(x[63:0]),   .k(code[9:7]),   .y(r2));
  qa_pe_rot  u_rot3 (.x(x[127:64]), .k(code[14:12]), .y(r3));
  qa_pe_rot  u_rot4 (.x(x[127:64]), .k(code[19:17]), .y(r4));
  qa_pe_acc4 u_acc  (.first(first), .acc(acc_q), .a(r1), .b(r2), .c(r3), .d(r4),
                     .t({code[16:15], code[11:10], code[6:5], code[1:0]}), .sum(sum));
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

// sum lane i = (first ? 0 : acc_i) + trit(a_i, t[1:0]) + trit(b_i, t[3:2]) + trit(c_i, t[5:4]) + trit(d_i, t[7:6]),
// written as one 6-operand sum: a trit term is (sext(e ? v : 0) XOR {n}) + n with e = t[0], n = t[1] & t[0]
// (two's complement negate = invert + 1), and the four +n carry-ins are one small operand.
module qa_pe_acc4 import qa_pkg::*; (
  input  logic              first,
  input  logic [8*ACC-1:0]  acc,
  input  logic [63:0]       a, b, c, d,
  input  logic [7:0]        t,
  output logic [8*ACC-1:0]  sum
);
  logic [3:0] e, n;
  logic [2:0] ncnt;
  always_comb begin
    for (int k = 0; k < 4; k++) begin
      e[k] = t[2*k];
      n[k] = t[2*k+1] & t[2*k];
    end
    ncnt = 3'(n[0]) + 3'(n[1]) + 3'(n[2]) + 3'(n[3]);
    for (int i = 0; i < 8; i++) begin
      logic signed [ACC-1:0] u0, u1, u2, u3;
      u0 = $signed({{(ACC-8){a[i*8+7] & e[0]}}, a[i*8 +: 8] & {8{e[0]}}}) ^ {ACC{n[0]}};
      u1 = $signed({{(ACC-8){b[i*8+7] & e[1]}}, b[i*8 +: 8] & {8{e[1]}}}) ^ {ACC{n[1]}};
      u2 = $signed({{(ACC-8){c[i*8+7] & e[2]}}, c[i*8 +: 8] & {8{e[2]}}}) ^ {ACC{n[2]}};
      u3 = $signed({{(ACC-8){d[i*8+7] & e[3]}}, d[i*8 +: 8] & {8{e[3]}}}) ^ {ACC{n[3]}};
      sum[i*ACC +: ACC] = (first ? '0 : acc[i*ACC +: ACC]) + u0 + u1 + u2 + u3 + ACC'(ncnt);
    end
  end
endmodule
