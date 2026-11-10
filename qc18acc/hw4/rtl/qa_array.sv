// v4 16 x 8 PE array (rows p = tile pixels, columns g = output groups) of the unchanged v3 qa_pe (hw3/rtl/qa_pe.sv:
// Kb = 2, fused acc + 4 trit terms).  Row p gets the 128-b pair word x[p]; column g gets the 20-b code pair code[g]
// (the weight word is broadcast to all 16 rows).  Shadow chains: per column TWO chains split by row bit 1 so the
// drain pops two pixels per read (ARCH v4 "Drain / PPU", compile4.layout.pair_rows):
//   chain A: rows 0 <- 1 <- 4 <- 5 <- 8 <- 9 <- 12 <- 13 (head row 0)
//   chain B: rows 2 <- 3 <- 6 <- 7 <- 10 <- 11 <- 14 <- 15 (head row 2)
// shift[g] moves both chains of column g one position towards their heads.
module qa_array import qa_pkg::*; (
  input  logic                   clk,
  input  logic                   vld, first, last,
  input  logic [NROW*128-1:0]    x,
  input  logic [8*20-1:0]        code,
  input  logic [7:0]             shift,
  output logic [8*8*ACC-1:0]     heads_a,      // column g chain A head at [g*8*ACC +: 8*ACC]
  output logic [8*8*ACC-1:0]     heads_b
);
  localparam int SW = 8 * ACC;
  logic [SW-1:0] sh [0:NROW-1][0:7];             // shadow register of PE (p, g)
  logic [SW-1:0] shin [0:NROW-1][0:7];
  genvar p, g;
  for (g = 0; g < 8; g++) begin : g_col
    assign heads_a[g*SW +: SW] = sh[0][g];
    assign heads_b[g*SW +: SW] = sh[2][g];
    for (p = 0; p < NROW; p++) begin : g_row
      // chain successor of row p: chain position c = 2 (p >> 2) + (p & 1); next row = position c + 1
      localparam int C = 2 * (p / 4) + (p % 2);
      localparam int NXT = (C == 7) ? -1 : 4 * ((C + 1) / 2) + ((C + 1) % 2) + (p % 4 >= 2 ? 2 : 0);
      if (NXT < 0) begin : g_end
        assign shin[p][g] = '0;
      end else begin : g_mid
        assign shin[p][g] = sh[NXT][g];
      end
      qa_pe u_pe (
        .clk(clk), .vld(vld), .first(first), .last(last), .x(x[p*128 +: 128]), .code(code[g*20 +: 20]),
        .shift(shift[g]), .sh_in(shin[p][g]), .sh_out(sh[p][g]));
    end
  end
endmodule
