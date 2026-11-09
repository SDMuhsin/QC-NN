// 8 x 8 PE array (rows p = tile pixels, columns g = output groups).  Row p gets activation word x[p], column g
// gets code[g].  Shadow chains: column g is a chain PE(7,g) -> ... -> PE(0,g); head = PE(0,g)'s shadow; shift[g]
// moves the column one position towards the head.
module qa_array import qa_pkg::*; (
  input  logic                clk,
  input  logic                vld, first, last,
  input  logic [8*64-1:0]     x,
  input  logic [8*10-1:0]     code,
  input  logic [7:0]          shift,
  output logic [8*8*ACC-1:0]  heads          // column g head at [g*8*ACC +: 8*ACC]
);
  localparam int SW = 8 * ACC;
  logic [9*8*SW-1:0] sh;                      // [(p*8+g)*SW +: SW] = shadow of PE(p, g); p = 8: chain input (zero)
  genvar p, g;
  for (g = 0; g < 8; g++) begin : g_col
    assign sh[(64+g)*SW +: SW] = '0;
    assign heads[g*8*ACC +: 8*ACC] = sh[g*SW +: SW];
    for (p = 0; p < 8; p++) begin : g_row
      qa_pe u_pe (
        .clk(clk), .vld(vld), .first(first), .last(last), .x(x[p*64 +: 64]), .code(code[g*10 +: 10]),
        .shift(shift[g]), .sh_in(sh[((p+1)*8+g)*SW +: SW]), .sh_out(sh[(p*8+g)*SW +: SW]));
    end
  end
endmodule
