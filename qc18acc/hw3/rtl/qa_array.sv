// v3 8 x 8 PE array (rows p = tile pixels, columns g = output groups).  Row p gets the 128-b pair word x[p], column
// g gets the 20-b code pair code[g] (even block [9:0], odd [19:10]).  Shadow chains as v2: column g is a chain
// PE(7,g) -> ... -> PE(0,g); head = PE(0,g)'s shadow; shift[g] moves column g one position towards the head (the v3
// drain pops two columns 2m, 2m + 1 per cycle).
module qa_array import qa_pkg::*; (
  input  logic                clk,
  input  logic                vld, first, last,
  input  logic [8*128-1:0]    x,
  input  logic [8*20-1:0]     code,
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
      qa_pe u_pe (
        .clk(clk), .vld(vld), .first(first), .last(last), .x(x[p*128 +: 128]), .code(code[g*20 +: 20]),
        .shift(shift[g]), .sh_in(sh[((p+1)*8+g)*SW +: SW]), .sh_out(sh[(p*8+g)*SW +: SW]));
    end
  end
endmodule
