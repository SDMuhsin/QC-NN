// Self-checking testbench of mac8 (RTL or gate-level netlist): random operands / enables / clears against a model.
module tb_mac8;
  import mac8_pkg::*;
  localparam int N = 2000;
  logic clk = 1'b0, rst_ni = 1'b0, en, clr;
  op_t  a, b;
  acc_t acc, ref_acc;
  op_t  ra, rb;
  logic ren, rclr;
  logic signed [15:0] rprod;
  assign rprod = ra * rb;
  int   errors = 0;

  mac8 dut (.clk, .rst_ni, .en_i(en), .clr_i(clr), .a_i(a), .b_i(b), .acc_o(acc));

  always #5 clk = ~clk;

  // reference model with the same two-stage timing
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      ra <= '0; rb <= '0; ren <= 1'b0; rclr <= 1'b0; ref_acc <= '0;
    end else begin
      ra <= a; rb <= b; ren <= en; rclr <= clr;
      if (rclr)     ref_acc <= '0;
      else if (ren) ref_acc <= ref_acc + acc_t'(rprod);
    end
  end

  initial begin
    {en, clr, a, b} = '0;
    repeat (3) @(negedge clk);
    rst_ni = 1'b1;
    for (int i = 0; i < N; i++) begin
      @(negedge clk);
      if (acc !== ref_acc) begin
        errors++;
        if (errors <= 5) $display("mismatch cycle %0d: acc %0d expected %0d", i, acc, ref_acc);
      end
      a   = op_t'($urandom);
      b   = op_t'($urandom);
      en  = ($urandom % 8) != 0;
      clr = ($urandom % 97) == 0;
    end
    if (errors == 0) $display("SMOKE PASS: %0d cycles, final acc %0d", N, acc);
    else             $display("SMOKE FAIL: %0d mismatches", errors);
    $finish;
  end
endmodule
