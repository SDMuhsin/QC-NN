// R4 per-hierarchy fallback (nocore.sh): timing/area stand-in for qb_core inside qb_chip.  Same ports; every input bit
// is loaded (so the logic feeding the core is kept) and every output bit is a flop (so the logic after the core sees
// a registered launch, as the real core's lane / b2 outputs).  Its own area is excluded: core = 8 x measured column.
module qb_core #(parameter int ROWS = 16, COLS = 8, KB = 36, MWF = 28, CREG = 0, WTP = 0, FTP = 0, PPOP = 0, BRG = 8) (
    input  logic                         clk, rst_n,
    input  logic [COLS*KB*8-1:0]         cd,
    input  logic [9:0]                   ctl,
    input  logic [ROWS*KB*8-1:0]         act,
    input  logic [COLS*8*17-1:0]         t2,
    output logic [ROWS*COLS*8-1:0]       b2,
    output logic                         b2_vld,
    input  logic                         f_vld, f_src, f_sh, p_ld,
    input  logic [COLS*8*(37+MWF+16)+4:0] pf,
    input  logic [4*COLS*8*17-1:0]       s_rd,
    output logic                         f_vld_o,
    output logic [4*COLS*8*17-1:0]       f_y,
    output logic [4*COLS*8-1:0]          f_b,
    input  logic                         w_vld, w_sh, w_ld,
    input  logic [COLS*8*79+2:0]         pw,
    input  logic [4*COLS*19-1:0]         w_r,
    output logic                         w_vld_o,
    output logic [4*COLS*19-1:0]         w_y,
    output logic [4*COLS-1:0]            w_b
);
    wire [$bits(cd)+$bits(ctl)+$bits(act)+$bits(t2)+4+$bits(pf)+$bits(s_rd)+3+$bits(pw)+$bits(w_r)-1:0] in_all =
        {cd, ctl, act, t2, f_vld, f_src, f_sh, p_ld, pf, s_rd, w_vld, w_sh, w_ld, pw, w_r};
    localparam int NI = $bits(in_all);
    localparam int NO = $bits(b2) + 2 + $bits(f_y) + $bits(f_b) + 1 + $bits(w_y) + $bits(w_b);
    localparam int S = (NI + NO - 1) / NO;
    wire [NO*S-1:0] in_pad = {(NO * S + NI - 1) / NI {in_all}};
    logic [NO-1:0] o;
    always_ff @(posedge clk) begin                      // o[i] = XOR over k of in_pad[k NO + i] (S <= 8 terms)
        logic [NO-1:0] t;
        t = '0;
        for (int k = 0; k < S; k++) t = t ^ in_pad[k * NO +: NO];
        o <= t;
    end
    assign {b2, b2_vld, f_vld_o, f_y, f_b, w_vld_o, w_y, w_b} = o;
endmodule
