// R7g: black-box FC macro for the Yosys head synthesis (syn.sh): the macro is not part of the pool comparison.
(* blackbox *)
module qbt_rfsp #(parameter int W = 128, parameter int N = 128) (
    input logic clk, ren, we, input logic [$clog2(N)-1:0] a, input logic [W-1:0] wd, output logic [W-1:0] q);
endmodule
