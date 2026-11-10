// v4 activation buffers A / B / C: 3 x 16 banks x 256 x 128 b, one qa_sram4 (256 x 128, write mask of 4 x 32 b) per
// bank = 48 macros (ARCH.md "v4": bank = index mod 16).  Registered macro boundaries and a DISTRIBUTED crossbar
// (ARCH addendum): no centralised bank <-> port mux; every stage below is a register stage of its own.
//
// Requesters (all presented combinationally in cycle t; the requester owns the roles' buffers, which differ):
//   ar   array / head reader: one buffer, any subset of the 16 banks, per-bank address.  Data path:
//        t+1 per-(buffer, bank) address / CEN flops at the macro pins -> t+2 Q -> t+3 per-macro output register
//        -> t+4 bank-select register (ar_rdata[k] = buffer ar_buf of bank k; 3:1, at the bank, loaded only for the
//        banks read).  ar_rdata of a read in cycle t is valid in cycle t + ALAT (4).
//   pr0, pr1  residual readers (PPU units 0 / 1; the host reads through pr0): one 128-b word each, distinct banks.
//        t+3 output registers -> t+4 group register (per port and group of 4 banks: 4 banks x 3 buffers) -> t+5
//        port register (4:1 over the groups).  pr_rdata valid in cycle t + RLAT (5).
//   pw0, pw1  writers (PPU units 0 / 1; the host writes through pw0 with a 64-b half mask): one word each, distinct
//        banks.  t+1 group register (per group of 4 banks, both ports) -> t+2 per-bank write-data register and the
//        per-(buffer, bank) address / CEN / WEN flops -> the macro writes at the end of t+2.
// Bank conflicts (two requests for one macro in the cycle its input flops are loaded) are checked in simulation.
module qa_actmem4 import qa_pkg::*; (
  input  logic                  clk,
  input  logic                  rst_n,
  // array / head reader
  input  logic [1:0]            ar_buf,
  input  logic [NBANK-1:0]      ar_ce,
  input  logic [NBANK*AAW-1:0]  ar_addr,
  output logic [NBANK*128-1:0]  ar_rdata,
  // residual / host readers
  input  logic [1:0]            pr_re,
  input  logic [1:0]            pr_buf,
  input  logic [2*LNB-1:0]      pr_bank,
  input  logic [2*AAW-1:0]      pr_addr,
  output logic [2*128-1:0]      pr_rdata,
  // writers
  input  logic [1:0]            pw_we,
  input  logic [1:0]            pw_buf,
  input  logic [2*LNB-1:0]      pw_bank,
  input  logic [2*AAW-1:0]      pw_addr,
  input  logic [2*2-1:0]        pw_hm,             // per port: 64-b half mask {hi, lo}
  input  logic [2*128-1:0]      pw_wdata
);
  localparam int NG = NBANK / 4;                   // bank groups of 4 (write fan-out, residual fan-in)

  // ---- write group stage (t+1) -------------------------------------------------------------------------------
  logic [1:0]   gw_we   [0:NG-1];
  logic [1:0]   gw_buf  [0:NG-1][0:1];
  logic [1:0]   gw_bank [0:NG-1][0:1];             // bank within the group
  logic [AAW-1:0] gw_addr [0:NG-1][0:1];
  logic [1:0]   gw_hm   [0:NG-1][0:1];
  logic [127:0] gw_data [0:NG-1][0:1];
  always_ff @(posedge clk) begin
    for (int q = 0; q < NG; q++)
      for (int i = 0; i < 2; i++) begin
        logic hit;
        hit = pw_we[i] && pw_bank[i*LNB+2 +: 2] == 2'(q);
        if (!rst_n) gw_we[q][i] <= 1'b0;
        else gw_we[q][i] <= hit;
        if (hit) begin
          gw_buf[q][i] <= pw_buf; gw_bank[q][i] <= pw_bank[i*LNB +: 2]; gw_addr[q][i] <= pw_addr[i*AAW +: AAW];
          gw_hm[q][i] <= pw_hm[i*2 +: 2]; gw_data[q][i] <= pw_wdata[i*128 +: 128];
        end
      end
  end

  // ---- read request pipeline (control only) ------------------------------------------------------------------
  logic [NBANK-1:0] arce1, arce2, arce3;
  logic [1:0] arb1, arb2, arb3;
  logic [1:0] pre1, pre2, pre3, pre4;
  logic [1:0] prb1, prb2, prb3;
  logic [LNB-1:0] prk1 [0:1], prk2 [0:1], prk3 [0:1], prk4 [0:1];
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      arce1 <= '0; arce2 <= '0; arce3 <= '0; pre1 <= '0; pre2 <= '0; pre3 <= '0; pre4 <= '0;
    end else begin
      arce1 <= ar_ce; arce2 <= arce1; arce3 <= arce2;
      pre1 <= pr_re; pre2 <= pre1; pre3 <= pre2; pre4 <= pre3;
    end
    arb1 <= ar_buf; arb2 <= arb1; arb3 <= arb2;
    prb1 <= pr_buf; prb2 <= prb1; prb3 <= prb2;
    for (int i = 0; i < 2; i++) begin
      prk1[i] <= pr_bank[i*LNB +: LNB]; prk2[i] <= prk1[i]; prk3[i] <= prk2[i]; prk4[i] <= prk3[i];
    end
  end

  // ---- banks: input flops + macro + output register ----------------------------------------------------------
  logic [127:0] rq [0:NBUF-1][0:NBANK-1];          // per-macro output registers (qa_sram4 rdata, valid t+3)
  genvar b, k;
  for (k = 0; k < NBANK; k++) begin : g_bank
    localparam int Q = k / 4, KL = k % 4;
    logic [127:0] wd_q;                              // per-bank write data (shared by the 3 buffers' macros)
    logic wsel;                                      // write port whose data this bank takes
    always_comb begin
      wsel = 1'b0;
      if (gw_we[Q][1] && gw_bank[Q][1] == 2'(KL)) wsel = 1'b1;
    end
    always_ff @(posedge clk)
      if ((gw_we[Q][0] && gw_bank[Q][0] == 2'(KL)) || (gw_we[Q][1] && gw_bank[Q][1] == 2'(KL)))
        wd_q <= gw_data[Q][wsel];
    for (b = 0; b < NBUF; b++) begin : g_buf
      logic s_ar, s_pr0, s_pr1, s_w0, s_w1;
      logic cen_q;
      logic [AWM-1:0] wen_q;
      logic [AAW-1:0] addr_q;
      always_comb begin
        s_ar  = ar_ce[k] && ar_buf == 2'(b);
        s_pr0 = pr_re[0] && pr_buf == 2'(b) && pr_bank[0 +: LNB] == LNB'(k);
        s_pr1 = pr_re[1] && pr_buf == 2'(b) && pr_bank[LNB +: LNB] == LNB'(k);
        s_w0  = gw_we[Q][0] && gw_buf[Q][0] == 2'(b) && gw_bank[Q][0] == 2'(KL);
        s_w1  = gw_we[Q][1] && gw_buf[Q][1] == 2'(b) && gw_bank[Q][1] == 2'(KL);
      end
      always_ff @(posedge clk) begin
        if (!rst_n) cen_q <= 1'b1;
        else cen_q <= !(s_ar || s_pr0 || s_pr1 || s_w0 || s_w1);
        if (s_ar || s_pr0 || s_pr1 || s_w0 || s_w1) begin
          wen_q  <= s_w0 ? ~{{2{gw_hm[Q][0][1]}}, {2{gw_hm[Q][0][0]}}} :
                    s_w1 ? ~{{2{gw_hm[Q][1][1]}}, {2{gw_hm[Q][1][0]}}} : '1;
          addr_q <= s_w0 ? gw_addr[Q][0] : s_w1 ? gw_addr[Q][1] : s_pr0 ? pr_addr[0 +: AAW] :
                    s_pr1 ? pr_addr[AAW +: AAW] : ar_addr[k*AAW +: AAW];
        end
      end
      qa_sram4 #(.WORDS(ADEPTH), .BITS(128), .WM(AWM)) u_ram (
        .clk(clk), .cen_n(cen_q), .wen_n(wen_q), .addr(addr_q), .wdata(wd_q), .rdata(rq[b][k]));
`ifndef SYNTHESIS
      always @(posedge clk)
        if (rst_n && (32'(s_ar) + 32'(s_pr0) + 32'(s_pr1) + 32'(s_w0) + 32'(s_w1)) > 1)
          $error("qa_actmem4: bank conflict buffer %0d bank %0d (ar %b pr %b%b w %b%b)", b, k, s_ar, s_pr0, s_pr1, s_w0, s_w1);
`endif
    end
    // array port: bank-select register (t+4), loaded only when this bank was read
    always_ff @(posedge clk) if (arce3[k]) ar_rdata[k*128 +: 128] <= rq[arb3][k];
  end

  // ---- residual / host read path: group register (t+4) -> port register (t+5) --------------------------------
  logic [127:0] gr [0:1][0:NG-1];
  always_ff @(posedge clk) begin
    for (int i = 0; i < 2; i++) begin
      for (int q = 0; q < NG; q++)
        if (pre3[i] && prk3[i][LNB-1:2] == 2'(q)) gr[i][q] <= rq[prb3][4*q + prk3[i][1:0]];
      if (pre4[i]) pr_rdata[i*128 +: 128] <= gr[i][prk4[i][LNB-1:2]];
    end
  end
endmodule
