// Registered signed 8x8 multiply-accumulate (flow smoke test).
// Cycle 1: operands, enable and clear registered.  Cycle 2: acc <= clr ? 0 : en ? acc + a * b : acc.
module mac8
  import mac8_pkg::*;
(
  input  logic clk,
  input  logic rst_ni,
  input  logic en_i,
  input  logic clr_i,
  input  op_t  a_i,
  input  op_t  b_i,
  output acc_t acc_o
);
  op_t  a_q, b_q;
  logic en_q, clr_q;
  acc_t acc_q;
  logic signed [15:0] prod;

  assign prod = a_q * b_q;

  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      a_q <= '0; b_q <= '0; en_q <= 1'b0; clr_q <= 1'b0;
    end else begin
      a_q <= a_i; b_q <= b_i; en_q <= en_i; clr_q <= clr_i;
    end
  end

  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni)    acc_q <= '0;
    else if (clr_q) acc_q <= '0;
    else if (en_q)  acc_q <= acc_q + acc_t'(prod);
  end

  assign acc_o = acc_q;
endmodule
