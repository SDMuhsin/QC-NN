// R4 (define QB_TECH): TSMC 65 nm implementation of qb_top's / qb_head's behavioural memories qbt_rfsp / qbt_rf2p
// (hw/rtl/qb_top.sv, same module names, parameters and ports; the behavioural ones are compiled out under QB_TECH).
// Each (W, N) maps to one ARM ACI macro of impl/r4/macros.txt (flow/tsmc65/sram/mc_gen.sh gen):
//   qbt_rfsp 144 x 204 -> qb_w_204x144m2  rf_sp_adv mux 2   weights, 16 lanes x 3 deep        (48)
//   qbt_rfsp 144 x 240 -> qb_p_240x144m2  rf_sp_adv mux 2   params bank (qb_prm)              (9)
//   qbt_rfsp 128 x 128 -> qb_i_128x128m1  rf_sp_adv mux 1   image IMG                         (4)
//   qbt_rfsp  64 x 408 -> qb_f_408x64m4   rf_sp_adv mux 4   FC (qb_head), 4 lanes x 4 deep    (16)
//   qbt_rfsp  80 x 624 -> qb_d_624x80m8   sram_sp_adv mux 8 qb_seq descriptors, DSCM = 1 only  (2)
//   qbt_rf2p 128 x 256 -> qb_s_256x128m1  rf_2p_adv mux 1   stream S, bit-write mask          (32)
//   qbt_rf2p 128 x 128 -> qb_b_128x128m1  rf_2p_adv mux 1   binary maps B1 / B2, bit mask     (8)
//   other              -> the behavioural model (none in qb_chip; a simulation message flags it)
// Pins: CEN / WEN active low; rf_2p: port A = read (CLKA, CENA, AA, QA), port B = write (CLKB, CENB, AB, DB, WENB per
// bit, active low = qbt mask wm inverted); EMA* 000, RETN 1.  Each macro clock (rf_2p: each port clock) is gated by an
// integrated clock gate CKLNQD1 enabled by the access (deselected macros see no clock edge; same as the qc18acc v2 ICG).
// Behaviour vs the qbt models: identical on every read (q = data of the last read until the next read).  Differences
// only on a write cycle of an rf_sp, where the macro's Q shows D (write-through) instead of holding: in qb_chip every
// rf_sp write is a host load (weights / params / FC before go, IMG while the stem is done and no IMG read is in flight),
// and no consumer samples q after a host write without a read in between (bench: logits + cycle-exact tile ends).
// rf_2p same-address read + write in one cycle: the macro returns X like qbt_rf2p (flagged by conf, err).
module qbt_rfsp #(parameter int W = 128, parameter int N = 128) (
    input  logic                 clk, ren, we,
    input  logic [$clog2(N)-1:0] a,
    input  logic [W-1:0]         wd,
    output logic [W-1:0]         q
);
    localparam bit IsW = W == 144 && N == 204, IsP = W == 144 && N == 240, IsI = W == 128 && N == 128,
                   IsF = W == 64 && N == 408, IsD = W == 80 && N == 624;
    if (IsW || IsP || IsI || IsF || IsD) begin : g_mac
        logic gclk;
        wire  cen = ~(ren | we), wen = ~we;
        CKLNQD1 u_cg (.TE(1'b0), .E(ren | we), .CP(clk), .Q(gclk));
        if (IsW)      begin : g_w qb_w_204x144m2 u_mac (.Q(q), .CLK(gclk), .CEN(cen), .WEN(wen), .A(a), .D(wd), .EMA(3'b000), .RETN(1'b1)); end
        else if (IsP) begin : g_p qb_p_240x144m2 u_mac (.Q(q), .CLK(gclk), .CEN(cen), .WEN(wen), .A(a), .D(wd), .EMA(3'b000), .RETN(1'b1)); end
        else if (IsI) begin : g_i qb_i_128x128m1 u_mac (.Q(q), .CLK(gclk), .CEN(cen), .WEN(wen), .A(a), .D(wd), .EMA(3'b000), .RETN(1'b1)); end
        else if (IsF) begin : g_f qb_f_408x64m4  u_mac (.Q(q), .CLK(gclk), .CEN(cen), .WEN(wen), .A(a), .D(wd), .EMA(3'b000), .RETN(1'b1)); end
        else          begin : g_d qb_d_624x80m8  u_mac (.Q(q), .CLK(gclk), .CEN(cen), .WEN(wen), .A(a), .D(wd), .EMA(3'b000), .RETN(1'b1)); end
    end else begin : g_beh
        logic [W-1:0] mem [N];
        always_ff @(posedge clk) begin
            if (we) mem[a] <= wd;
            else if (ren) q <= mem[a];
        end
`ifndef SYNTHESIS
        initial $display("qb_mem_tech %m: no macro for rf_sp %0d x %0d, behavioural", N, W);
`endif
    end
endmodule

module qbt_rf2p #(parameter int W = 128, parameter int N = 256) (
    input  logic                 clk, ren, we,
    input  logic [$clog2(N)-1:0] ra, wa,
    input  logic [W-1:0]         wd, wm,
    output logic [W-1:0]         q,
    output logic                 conf
);
    assign conf = ren && we && ra == wa;
    localparam bit IsS = W == 128 && N == 256, IsB = W == 128 && N == 128;
    if (IsS || IsB) begin : g_mac
        logic gca, gcb;
        CKLNQD1 u_cga (.TE(1'b0), .E(ren), .CP(clk), .Q(gca));
        CKLNQD1 u_cgb (.TE(1'b0), .E(we),  .CP(clk), .Q(gcb));
        if (IsS) begin : g_s
            qb_s_256x128m1 u_mac (.QA(q), .CLKA(gca), .CENA(~ren), .AA(ra), .CLKB(gcb), .CENB(~we), .WENB(~wm), .AB(wa),
                                  .DB(wd), .EMAA(3'b000), .EMAB(3'b000), .RETN(1'b1));
        end else begin : g_b
            qb_b_128x128m1 u_mac (.QA(q), .CLKA(gca), .CENA(~ren), .AA(ra), .CLKB(gcb), .CENB(~we), .WENB(~wm), .AB(wa),
                                  .DB(wd), .EMAA(3'b000), .EMAB(3'b000), .RETN(1'b1));
        end
    end else begin : g_beh
        logic [W-1:0] mem [N];
        always_ff @(posedge clk) begin
            if (ren) q <= conf ? 'x : mem[ra];
            if (we) mem[wa] <= (mem[wa] & ~wm) | (wd & wm);
        end
`ifndef SYNTHESIS
        initial $display("qb_mem_tech %m: no macro for rf_2p %0d x %0d, behavioural", N, W);
`endif
    end
endmodule
