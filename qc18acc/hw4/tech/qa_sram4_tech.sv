// v4: TSMC 65 nm implementation of qa_sram4 (same module name, parameters and ports as hw4/rtl/qa_sram4.sv, which
// it replaces in hw4/tech/qc18acc_tech.f).  Each instance shape maps to one compiled ARM macro of impl/v4/macros.txt:
//    256 x 128, WM 4 -> qa_act_256x128m2  rf_sp_adv   mux 2, write mask 4 x 32 b   activation banks (48x)
//   4096 x 80        -> qa_wgt_4096x80m8  sram_sp_adv mux 8                        weight banks (2 halves x 3)
//   4096 x 72        -> qa_par_4096x72m8  sram_sp_adv mux 8                        param banks (2x)
//    256 x 32        -> qa_dsc_256x32m2   rf_sp_adv   mux 2                        descriptor RAM (1x)
// The macro pins CEN / WEN / A / D are wired straight to the caller's flops (registered macro boundary); CLK is gated
// by a CKLNQD enabled by the access (E = !cen_n, v2 practice); EMA 000, RETN 1.  The output register rdata (loaded
// one cycle after a read access, from Q) is the macro's own output register: no hold mux after Q (the macros are
// write-through; rdata simply does not load after a write), the register keeps the last read word as in qa_sram4.
module qa_sram4 #(
  parameter int WORDS = 256,
  parameter int BITS  = 128,
  parameter int WM    = 1,
  parameter int AW    = (WORDS > 1) ? $clog2(WORDS) : 1
) (
  input  logic            clk,
  input  logic            cen_n,
  input  logic [WM-1:0]   wen_n,
  input  logic [AW-1:0]   addr,
  input  logic [BITS-1:0] wdata,
  output logic [BITS-1:0] rdata
);
  localparam bit IsAct = WORDS == 256  && BITS == 128 && WM == 4;
  localparam bit IsWgt = WORDS == 4096 && BITS == 80  && WM == 1;
  localparam bit IsPar = WORDS == 4096 && BITS == 72  && WM == 1;
  localparam bit IsDsc = WORDS == 256  && BITS == 32  && WM == 1;

  if (IsAct || IsWgt || IsPar || IsDsc) begin : g_mac
    logic [BITS-1:0] q;
    logic rd_q, gclk;
    CKLNQD2 u_cg (.TE(1'b0), .E(!cen_n), .CP(clk), .Q(gclk));
    if (IsAct) begin : g_act
      qa_act_256x128m2 u_mac (.Q(q), .CLK(gclk), .CEN(cen_n), .WEN(wen_n), .A(addr), .D(wdata), .EMA(3'b000), .RETN(1'b1));
    end else if (IsWgt) begin : g_wgt
      qa_wgt_4096x80m8 u_mac (.Q(q), .CLK(gclk), .CEN(cen_n), .WEN(wen_n), .A(addr), .D(wdata), .EMA(3'b000), .RETN(1'b1));
    end else if (IsPar) begin : g_par
      qa_par_4096x72m8 u_mac (.Q(q), .CLK(gclk), .CEN(cen_n), .WEN(wen_n), .A(addr), .D(wdata), .EMA(3'b000), .RETN(1'b1));
    end else begin : g_dsc
      qa_dsc_256x32m2  u_mac (.Q(q), .CLK(gclk), .CEN(cen_n), .WEN(wen_n), .A(addr), .D(wdata), .EMA(3'b000), .RETN(1'b1));
    end
    always_ff @(posedge clk) begin
      rd_q <= !cen_n && (&wen_n);
      if (rd_q) rdata <= q;
    end
  end else begin : g_ff
    localparam int GB = BITS / WM;
    logic [BITS-1:0] mem [0:WORDS-1];
    logic [BITS-1:0] q;
    logic rd_q;
    always_ff @(posedge clk) begin
      rd_q <= !cen_n && (&wen_n);
      if (!cen_n) begin
        if (&wen_n) q <= mem[addr];
        else for (int g = 0; g < WM; g++) if (!wen_n[g]) mem[addr][g*GB +: GB] <= wdata[g*GB +: GB];
      end
      if (rd_q) rdata <= q;
    end
`ifndef SYNTHESIS
    initial $display("qa_sram4_tech %m: no macro for %0d x %0d / %0d, flip-flops", WORDS, BITS, WM);
`endif
  end
`ifndef SYNTHESIS
  always @(posedge clk) if (cen_n === 1'b0 && addr >= WORDS) $error("qa_sram4 %m: address %0d out of range", addr);
`endif
endmodule
