// 8 x 8 ablation array (qc18acc/ablation): the v2 qa_array with qab_pe (TERNARY V = 1 / INT8 V = 2) instead of
// qa_pe; column g gets its WB-bit weight block w[g], everything else (rows = tile pixels, shadow chains towards
// p = 0, heads) is qa_array.
module qab_array #(parameter int V = 1, parameter int WB = 128, parameter int ACC = 21) (
  input  logic                clk,
  input  logic                vld, first, last,
  input  logic [8*64-1:0]     x,
  input  logic [8*WB-1:0]     w,
  input  logic [7:0]          shift,
  output logic [8*8*ACC-1:0]  heads          // column g head at [g*8*ACC +: 8*ACC]
);
  localparam int SW = 8 * ACC;
  logic [9*8*SW-1:0] sh;
  genvar p, g;
  for (g = 0; g < 8; g++) begin : g_col
    assign sh[(64+g)*SW +: SW] = '0;
    assign heads[g*8*ACC +: 8*ACC] = sh[g*SW +: SW];
    for (p = 0; p < 8; p++) begin : g_row
      qab_pe #(.V(V), .WB(WB), .ACC(ACC)) u_pe (
        .clk(clk), .vld(vld), .first(first), .last(last), .x(x[p*64 +: 64]), .w(w[g*WB +: WB]),
        .shift(shift[g]), .sh_in(sh[((p+1)*8+g)*SW +: SW]), .sh_out(sh[(p*8+g)*SW +: SW]));
    end
  end
endmodule
