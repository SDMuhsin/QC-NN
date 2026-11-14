// Local (Verilator) stand-ins for the ARM macro pinouts used by qb_mem_tech.sv and the CKLNQD1 clock gate, written
// from the pin semantics only (no kit file): rf_sp: CEN = 0 & WEN = 0 write (Q = D, write-through), CEN = 0 & WEN = 1
// read, CEN = 1 hold; rf_2p: port A read (QA holds when CENA = 1), port B write with per-bit WENB (active low);
// same-address read + write -> QA = X.  The tau runs use the compiler's own Verilog models instead.
module qb_arm_rfsp_beh #(parameter int W = 8, parameter int N = 8, parameter int AW = 3) (
    output logic [W-1:0] Q, input logic CLK, CEN, WEN, input logic [AW-1:0] A, input logic [W-1:0] D);
    logic [W-1:0] mem [N];
    always_ff @(posedge CLK) if (!CEN) begin
        if (!WEN) begin mem[A] <= D; Q <= D; end else Q <= mem[A];
    end
endmodule
module qb_arm_rf2p_beh #(parameter int W = 8, parameter int N = 8, parameter int AW = 3) (
    output logic [W-1:0] QA, input logic CLKA, CENA, input logic [AW-1:0] AA, input logic CLKB, CENB,
    input logic [W-1:0] WENB, input logic [AW-1:0] AB, input logic [W-1:0] DB);
    logic [W-1:0] mem [N];
    logic [AW-1:0] wa_l; logic we_l;
    always_ff @(posedge CLKB) if (!CENB) mem[AB] <= (mem[AB] & WENB) | (DB & ~WENB);
    always_ff @(posedge CLKA) if (!CENA) QA <= mem[AA];
endmodule
`define QB_ARM_SP(NAME, W, N, AW) \
module NAME (output logic [W-1:0] Q, input logic CLK, CEN, WEN, input logic [AW-1:0] A, input logic [W-1:0] D, \
             input logic [2:0] EMA, input logic RETN); \
    qb_arm_rfsp_beh #(W, N, AW) u (.*); \
endmodule
`define QB_ARM_2P(NAME, W, N, AW) \
module NAME (output logic [W-1:0] QA, input logic CLKA, CENA, input logic [AW-1:0] AA, input logic CLKB, CENB, \
             input logic [W-1:0] WENB, input logic [AW-1:0] AB, input logic [W-1:0] DB, input logic [2:0] EMAA, EMAB, \
             input logic RETN); \
    qb_arm_rf2p_beh #(W, N, AW) u (.*); \
endmodule
`QB_ARM_SP(qb_w_204x144m2, 144, 204, 8)
`QB_ARM_SP(qb_p_240x144m2, 144, 240, 8)
`QB_ARM_SP(qb_i_128x128m1, 128, 128, 7)
`QB_ARM_SP(qb_f_408x64m4, 64, 408, 9)
`QB_ARM_SP(qb_d_624x80m8, 80, 624, 10)
`QB_ARM_2P(qb_s_256x128m1, 128, 256, 8)
`QB_ARM_2P(qb_b_128x128m1, 128, 128, 7)
module CKLNQD1 (input logic TE, E, CP, output logic Q);
    logic en;
    always_latch if (!CP) en = E | TE;
    assign Q = CP & en;
endmodule
