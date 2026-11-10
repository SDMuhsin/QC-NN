// Ablation PEs at Kb = 2 (qc18acc/ablation, v3 geometry): same interface, registers and control as the v3 qa_pe (two
// 8x8 blocks per cycle, output-stationary, first step of a tile overwrites, last step captures into the shadow
// register, shadow shifts along the column chain); only the block arithmetic and the widths differ.  Row input x =
// one 128-b pair word (x[63:0] = even block's 8 inputs, x[127:64] = odd block's), as v3.  Like the v3 QC PE (one fused
// trit + 4-term + accumulate sum, qa_pe_acc4), the whole lane update is ONE combinational sum in u_acc:
//   TERNARY  w = 2 x 64 trits (block h = 0 even / 1 odd, lane i input j at bits [128h + 2(8i+j) +: 2]; 01 = +1,
//            11 = -1, 00 / 10 = 0):  sum_i = (first ? 0 : acc_i) + sum_{h,j} trit_hij x_hj   (16 terms), ACC 21
//   INT8     w = 2 x 64 int8 (lane i input j of block h at bits [512h + 8(8i+j) +: 8]):
//            sum_i = (first ? 0 : acc_i) + sum_{h,j} w_hij x_hj   (16 signed 8x8 products), ACC 32
module qab3_pe #(parameter int V = 1, parameter int WB = 256, parameter int ACC = 21) (
  input  logic              clk,
  input  logic              vld, first, last,
  input  logic [127:0]      x,
  input  logic [WB-1:0]     w,
  input  logic              shift,
  input  logic [8*ACC-1:0]  sh_in,
  output logic [8*ACC-1:0]  sh_out
);
  logic [8*ACC-1:0] acc_q, sum;
  if (V == 1) begin : g_t
    qab3_acc_tern #(.ACC(ACC)) u_acc (.first(first), .acc(acc_q), .x(x), .w(w), .sum(sum));
  end else begin : g_i
    qab3_acc_int8 #(.ACC(ACC)) u_acc (.first(first), .acc(acc_q), .x(x), .w(w), .sum(sum));
  end
  always_ff @(posedge clk) begin
    if (vld && !last) acc_q <= sum;
    if (vld && last) sh_out <= sum;
    else if (shift) sh_out <= sh_in;
  end
endmodule

module qab3_acc_tern #(parameter int ACC = 21) (
  input  logic              first,
  input  logic [8*ACC-1:0]  acc,
  input  logic [127:0]      x,
  input  logic [255:0]      w,
  output logic [8*ACC-1:0]  sum
);
  function automatic logic signed [ACC-1:0] trit(input logic [7:0] v, input logic [1:0] t);
    case (t)
      2'b01:   trit = ACC'($signed(v));
      2'b11:   trit = -ACC'($signed(v));
      default: trit = '0;
    endcase
  endfunction
  always_comb
    for (int i = 0; i < 8; i++) begin
      logic signed [ACC-1:0] a;
      a = first ? '0 : $signed(acc[i*ACC +: ACC]);
      for (int h = 0; h < 2; h++)
        for (int j = 0; j < 8; j++) a = a + trit(x[h*64 + j*8 +: 8], w[h*128 + (i*8+j)*2 +: 2]);
      sum[i*ACC +: ACC] = a;
    end
endmodule

module qab3_acc_int8 #(parameter int ACC = 32) (
  input  logic              first,
  input  logic [8*ACC-1:0]  acc,
  input  logic [127:0]      x,
  input  logic [1023:0]     w,
  output logic [8*ACC-1:0]  sum
);
  always_comb
    for (int i = 0; i < 8; i++) begin
      logic signed [ACC-1:0] a;
      a = first ? '0 : $signed(acc[i*ACC +: ACC]);
      for (int h = 0; h < 2; h++)
        for (int j = 0; j < 8; j++) a = a + ACC'($signed(x[h*64 + j*8 +: 8]) * $signed(w[h*512 + (i*8+j)*8 +: 8]));
      sum[i*ACC +: ACC] = a;
    end
endmodule

// 8 x 8 ablation array at Kb = 2: the v3 qa_array with qab3_pe; row p gets the 128-b pair word x[p], column g its
// WB-bit weight word w[g] (even + odd block); shadow chains / heads as qa_array.
module qab3_array #(parameter int V = 1, parameter int WB = 256, parameter int ACC = 21) (
  input  logic                clk,
  input  logic                vld, first, last,
  input  logic [8*128-1:0]    x,
  input  logic [8*WB-1:0]     w,
  input  logic [7:0]          shift,
  output logic [8*8*ACC-1:0]  heads
);
  localparam int SW = 8 * ACC;
  logic [9*8*SW-1:0] sh;
  genvar p, g;
  for (g = 0; g < 8; g++) begin : g_col
    assign sh[(64+g)*SW +: SW] = '0;
    assign heads[g*8*ACC +: 8*ACC] = sh[g*SW +: SW];
    for (p = 0; p < 8; p++) begin : g_row
      qab3_pe #(.V(V), .WB(WB), .ACC(ACC)) u_pe (
        .clk(clk), .vld(vld), .first(first), .last(last), .x(x[p*128 +: 128]), .w(w[g*WB +: WB]),
        .shift(shift[g]), .sh_in(sh[((p+1)*8+g)*SW +: SW]), .sh_out(sh[(p*8+g)*SW +: SW]));
    end
  end
endmodule
