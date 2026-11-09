// Unit test: qa_ppu_lane (RELU, RAW16, RES_ID, RES_R; negative values, rounding ties) against vectors from
// ppu_vectors.py (golden arithmetic).  +VEC=<file>.  Prints PASS / FAIL.
`timescale 1ns/1ps
module tb_ppu;
  import qa_pkg::*;
  logic clk = 0;
  always #1 clk = ~clk;
  logic [5:0] e = '0;
  logic [1:0] mode;
  logic [ACC-1:0] acc;
  logic [31:0] bias;
  logic [30:0] m0, idm0;
  logic [5:0] sh, idsh;
  logic d;
  logic [7:0] rlo, rhi, out6, out6_hi;
  qa_ppu_lane dut (.clk, .e1(e[0]), .e2(e[1]), .e3(e[2]), .e4(e[3]), .e5(e[4]), .e6(e[5]), .mode, .acc, .bias, .m0,
                   .sh, .d, .rlo, .rhi, .idm0, .idsh, .out6, .out6_hi);
  initial begin
    integer fd, r, n, errors;
    reg [8*512-1:0] fn;
    logic [31:0] f_mode, f_acc, f_bias, f_m0, f_sh, f_d, f_lo, f_hi, f_idm0, f_idsh, f_o, f_oh;
    if (!$value$plusargs("VEC=%s", fn)) fn = "ppu_vectors.hex";
    fd = $fopen(fn, "r");
    if (fd == 0) begin $display("tb_ppu: FAIL, cannot open vectors"); $finish; end
    n = 0; errors = 0;
    while ($fscanf(fd, "%h %h %h %h %h %h %h %h %h %h %h %h\n", f_mode, f_acc, f_bias, f_m0, f_sh, f_d, f_lo, f_hi,
                   f_idm0, f_idsh, f_o, f_oh) == 12) begin
      @(negedge clk);
      mode = f_mode; acc = f_acc; bias = f_bias; m0 = f_m0; sh = f_sh; d = f_d; idm0 = f_idm0; idsh = f_idsh;
      e = 6'b000001;
      @(negedge clk); e = 6'b000010;
      @(negedge clk); e = 6'b000100; rlo = f_lo;            // residual low byte / q in the r2 cycle
      @(negedge clk); e = 6'b001000; rhi = f_hi; rlo = 'x;  // R high byte in the r3 cycle
      @(negedge clk); e = 6'b010000; rhi = 'x;
      @(negedge clk); e = 6'b100000;
      @(negedge clk); e = 6'b000000;
      if (out6 !== f_o[7:0] || (mode == M_RAW16 && out6_hi !== f_oh[7:0])) begin
        if (errors < 10) $display("vector %0d mode %0d acc %0d: got %h %h exp %h %h", n, mode, $signed(acc), out6,
                                  out6_hi, f_o[7:0], f_oh[7:0]);
        errors = errors + 1;
      end
      n = n + 1;
    end
    $display("tb_ppu: %0d vectors, %0s", n, (errors || n == 0) ? "FAIL" : "PASS");
    $finish;
  end
endmodule
