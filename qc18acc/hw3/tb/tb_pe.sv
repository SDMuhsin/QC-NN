// v3 unit test: qa_pe (2 blocks per step) against a behavioural model (random code pairs incl. the illegal trit 10
// = 0, random int8 pair words, random tile lengths, capture + shadow shift).  Prints PASS / FAIL.
`timescale 1ns/1ps
module tb_pe;
  import qa_pkg::*;
  logic clk = 0;
  always #1 clk = ~clk;
  logic vld = 0, first = 0, last = 0, shift = 0;
  logic [127:0] x;
  logic [19:0] code;
  logic [8*ACC-1:0] sh_in, sh_out;
  qa_pe dut (.clk, .vld, .first, .last, .x, .code, .shift, .sh_in, .sh_out);
  integer errors = 0, ntile = 0;
  integer ref_acc [0:7];
  function automatic integer tv(input logic [1:0] t);
    tv = t == 2'b01 ? 1 : (t == 2'b11 ? -1 : 0);
  endfunction
  initial begin
    integer K, s;
    for (int t = 0; t < 400; t++) begin
      K = 1 + $urandom % 12;
      for (int i = 0; i < 8; i++) ref_acc[i] = 0;
      s = 0;
      while (s < K) begin
        @(negedge clk);
        x = {$urandom, $urandom, $urandom, $urandom}; code = $urandom; vld = ($urandom % 4) != 0;
        first = vld && s == 0; last = vld && s == K - 1; shift = 0;
        if (vld) begin
          for (int i = 0; i < 8; i++)
            for (int h = 0; h < 2; h++)
              ref_acc[i] = ref_acc[i] + tv(code[10*h+1 -: 2]) * $signed(x[64*h + ((i + code[10*h+4 -: 3]) % 8)*8 +: 8])
                                      + tv(code[10*h+6 -: 2]) * $signed(x[64*h + ((i + code[10*h+9 -: 3]) % 8)*8 +: 8]);
          s = s + 1;
        end
      end
      @(negedge clk); vld = 0; first = 0; last = 0;
      for (int i = 0; i < 8; i++)
        if ($signed(sh_out[i*ACC +: ACC]) !== ref_acc[i]) begin
          if (errors < 5) $display("tile %0d lane %0d: got %0d exp %0d", t, i, $signed(sh_out[i*ACC +: ACC]), ref_acc[i]);
          errors = errors + 1;
        end
      sh_in = {8{20'h12345}}; shift = 1; @(negedge clk); shift = 0;
      if (sh_out !== sh_in) errors = errors + 1;
      ntile = ntile + 1;
    end
    $display("tb_pe (v3): %0d tiles, %0s", ntile, errors ? "FAIL" : "PASS");
    $finish;
  end
endmodule
