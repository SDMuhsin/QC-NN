// TSMC 65 nm implementation of qa_sram (same module name, parameters and ports as hw/rtl/qa_sram.sv, which it
// replaces in the file list tech/qc18acc_tech.f).  Each instance shape maps to one compiled ARM macro of
// impl/macros.txt (flow/tsmc65/sram/mc_gen.sh gen):
//   1024 x 64  -> qa_act_1024x64m8  sram_sp_adv mux 8   activation banks (24x)
//   4096 x 80  -> qa_wgt_4096x80m8  sram_sp_adv mux 8   weight banks (6x)
//   4096 x 72  -> qa_par_4096x72m8  sram_sp_adv mux 8   param banks (2x)
//    256 x 32  -> qa_dsc_256x32m2   rf_sp_adv   mux 2   descriptor RAM (1x)
//   other      -> flip-flop array with the qa_sram behaviour (none in the design; a simulation warning flags it)
// Macro pins: CEN / WEN active low (one global WEN, no write mask), EMA 000, RETN 1 (no retention).
// Behaviour kept identical to qa_sram: the macros are write-through (Q shows D after a write), qa_sram's rdata is
// "last read data, held over writes and idle cycles".  rd_last_q = the last access was a read (the macro output
// still holds its data); on a write that follows a read the read data is captured in hold_q and rdata switches to
// it until the next read.  No reset (qa_sram has none): before the first access rdata is X in both models.
module qa_sram #(
  parameter int WORDS = 1024,
  parameter int BITS  = 64,
  parameter int AW    = (WORDS > 1) ? $clog2(WORDS) : 1
) (
  input  logic            clk,
  input  logic            ce,
  input  logic            we,
  input  logic [AW-1:0]   addr,
  input  logic [BITS-1:0] wdata,
  output logic [BITS-1:0] rdata
);
  localparam bit IsAct = WORDS == 1024 && BITS == 64;
  localparam bit IsWgt = WORDS == 4096 && BITS == 80;
  localparam bit IsPar = WORDS == 4096 && BITS == 72;
  localparam bit IsDsc = WORDS == 256  && BITS == 32;

  if (IsAct || IsWgt || IsPar || IsDsc) begin : g_mac
    logic [BITS-1:0] q, hold_q;
    logic rd_last_q;
    if (IsAct) begin : g_act
      qa_act_1024x64m8 u_mac (.Q(q), .CLK(clk), .CEN(~ce), .WEN(~we), .A(addr), .D(wdata), .EMA(3'b000), .RETN(1'b1));
    end else if (IsWgt) begin : g_wgt
      qa_wgt_4096x80m8 u_mac (.Q(q), .CLK(clk), .CEN(~ce), .WEN(~we), .A(addr), .D(wdata), .EMA(3'b000), .RETN(1'b1));
    end else if (IsPar) begin : g_par
      qa_par_4096x72m8 u_mac (.Q(q), .CLK(clk), .CEN(~ce), .WEN(~we), .A(addr), .D(wdata), .EMA(3'b000), .RETN(1'b1));
    end else begin : g_dsc
      qa_dsc_256x32m2  u_mac (.Q(q), .CLK(clk), .CEN(~ce), .WEN(~we), .A(addr), .D(wdata), .EMA(3'b000), .RETN(1'b1));
    end
    always_ff @(posedge clk) begin
      if (ce) rd_last_q <= ~we;
      if (ce && we && rd_last_q) hold_q <= q;
    end
    assign rdata = rd_last_q ? q : hold_q;
  end else begin : g_ff
    logic [BITS-1:0] mem [0:WORDS-1];
    always_ff @(posedge clk) begin
      if (ce) begin
        if (we) mem[addr] <= wdata;
        else    rdata     <= mem[addr];
      end
    end
`ifndef SYNTHESIS
    initial $display("qa_sram_tech %m: no macro for %0d x %0d, flip-flops", WORDS, BITS);
`endif
  end
`ifndef SYNTHESIS
  always @(posedge clk) if (ce === 1'b1 && addr >= WORDS) $error("qa_sram %m: address %0d out of range", addr);
`endif
endmodule
