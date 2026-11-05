// macro-hook test: 8 input flops -> FAKERAM -> 8 output flops
module macro_test (clk, d, q);
  input clk;
  input [7:0] d;
  output [7:0] q;
  wire [7:0] dq, rq;
  DFQD1 din_0 (.D(d[0]), .CP(clk), .Q(dq[0]));
  DFQD1 dout_0 (.D(rq[0]), .CP(clk), .Q(q[0]));
  DFQD1 din_1 (.D(d[1]), .CP(clk), .Q(dq[1]));
  DFQD1 dout_1 (.D(rq[1]), .CP(clk), .Q(q[1]));
  DFQD1 din_2 (.D(d[2]), .CP(clk), .Q(dq[2]));
  DFQD1 dout_2 (.D(rq[2]), .CP(clk), .Q(q[2]));
  DFQD1 din_3 (.D(d[3]), .CP(clk), .Q(dq[3]));
  DFQD1 dout_3 (.D(rq[3]), .CP(clk), .Q(q[3]));
  DFQD1 din_4 (.D(d[4]), .CP(clk), .Q(dq[4]));
  DFQD1 dout_4 (.D(rq[4]), .CP(clk), .Q(q[4]));
  DFQD1 din_5 (.D(d[5]), .CP(clk), .Q(dq[5]));
  DFQD1 dout_5 (.D(rq[5]), .CP(clk), .Q(q[5]));
  DFQD1 din_6 (.D(d[6]), .CP(clk), .Q(dq[6]));
  DFQD1 dout_6 (.D(rq[6]), .CP(clk), .Q(q[6]));
  DFQD1 din_7 (.D(d[7]), .CP(clk), .Q(dq[7]));
  DFQD1 dout_7 (.D(rq[7]), .CP(clk), .Q(q[7]));
  FAKERAM u_ram (.CLK(clk), .D(dq), .Q(rq));
endmodule
