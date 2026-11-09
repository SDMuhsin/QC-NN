// QC block PE: one 8x8 block per cycle, output-stationary.  y[i] = t1 x[(i+k1) mod 8] + t2 x[(i+k2) mod 8]
// (code bits [4:0] = {k1, t1}, [9:5] = {k2, t2}; trit 01 = +1, 11 = -1, 00 / 10 = 0), accumulated into 8 x 20-b
// accumulators (first step of a tile overwrites).  Path: rotator (3-level mux) -> trit (negate / zero) -> 3-input
// add -> acc.  The last step of a tile writes the sum into the shadow register instead (capture, 1 cycle); the
// shadow shifts along the column chain (towards p = 0) when the drain controller pops the column head.
module qa_pe import qa_pkg::*; (
  input  logic              clk,
  input  logic              vld, first, last,
  input  logic [63:0]       x,
  input  logic [9:0]        code,
  input  logic              shift,
  input  logic [8*ACC-1:0]  sh_in,
  output logic [8*ACC-1:0]  sh_out
);
  logic [8*ACC-1:0] acc, sum;
  wire [2:0] k1 = code[4:2], k2 = code[9:7];
  wire [1:0] t1 = code[1:0], t2 = code[6:5];

  function automatic logic signed [8:0] trit(input logic [7:0] v, input logic [1:0] t);
    case (t)
      2'b01:   trit = $signed({v[7], v});
      2'b11:   trit = -$signed({v[7], v});
      default: trit = 9'sd0;
    endcase
  endfunction

  always_comb begin
    for (int i = 0; i < 8; i++) begin
      logic signed [ACC-1:0] a, b, base;
      a = trit(x[3'(i + k1)*8 +: 8], t1);
      b = trit(x[3'(i + k2)*8 +: 8], t2);
      base = first ? '0 : $signed(acc[i*ACC +: ACC]);
      sum[i*ACC +: ACC] = base + a + b;
    end
  end
  always_ff @(posedge clk) begin
    if (vld && !last) acc <= sum;
    if (vld && last) sh_out <= sum;
    else if (shift) sh_out <= sh_in;
  end
endmodule
