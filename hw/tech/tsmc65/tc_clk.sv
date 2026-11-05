// TSMC 65 nm (tcbn65gplus) implementation of the tech_cells_generic clock cells (tc_clk.sv), same ports.
// Each cell is one balanced clock cell of the library (CK* family, drive 1; synthesis may resize them):
//   tc_clk_and2 CKAN2D1, tc_clk_buffer CKBD1, tc_clk_gating CKLNQD1 (latch-based ICG, test enable),
//   tc_clk_inverter CKND1, tc_clk_mux2 CKMUX2D1 (not glitch free, as the generic cell), tc_clk_xor2 CKXOR2D1,
//   tc_clk_or2 CKND2D1 on inverted inputs (the library has no clock OR).
// tc_clk_delay stays behavioural and simulation-only, as in the generic cells.

module tc_clk_and2 (
  input  logic clk0_i,
  input  logic clk1_i,
  output logic clk_o
);
  CKAN2D1 i_cell (.A1(clk0_i), .A2(clk1_i), .Z(clk_o));
endmodule

module tc_clk_buffer (
  input  logic clk_i,
  output logic clk_o
);
  CKBD1 i_cell (.I(clk_i), .Z(clk_o));
endmodule

module tc_clk_gating #(
  // hint of the generic cell (power-only gates could be removed); every gate is kept here
  parameter bit IS_FUNCTIONAL = 1'b1
) (
  input  logic clk_i,
  input  logic en_i,
  input  logic test_en_i,
  output logic clk_o
);
  CKLNQD1 i_cell (.CP(clk_i), .E(en_i), .TE(test_en_i), .Q(clk_o));
endmodule

module tc_clk_inverter (
  input  logic clk_i,
  output logic clk_o
);
  CKND1 i_cell (.I(clk_i), .ZN(clk_o));
endmodule

module tc_clk_mux2 (
  input  logic clk0_i,
  input  logic clk1_i,
  input  logic clk_sel_i,
  output logic clk_o
);
  CKMUX2D1 i_cell (.I0(clk0_i), .I1(clk1_i), .S(clk_sel_i), .Z(clk_o));
endmodule

module tc_clk_xor2 (
  input  logic clk0_i,
  input  logic clk1_i,
  output logic clk_o
);
  CKXOR2D1 i_cell (.A1(clk0_i), .A2(clk1_i), .Z(clk_o));
endmodule

module tc_clk_or2 (
  input  logic clk0_i,
  input  logic clk1_i,
  output logic clk_o
);
  logic clk0_n, clk1_n;
  CKND1   i_inv0 (.I(clk0_i), .ZN(clk0_n));
  CKND1   i_inv1 (.I(clk1_i), .ZN(clk1_n));
  CKND2D1 i_nand (.A1(clk0_n), .A2(clk1_n), .ZN(clk_o));
endmodule

`ifndef SYNTHESIS
module tc_clk_delay #(
  parameter int unsigned Delay = 300ps
) (
  input  logic in_i,
  output logic out_o
);
// pragma translate_off
`ifndef VERILATOR
  assign #(Delay) out_o = in_i;
`endif
// pragma translate_on
endmodule
`endif
