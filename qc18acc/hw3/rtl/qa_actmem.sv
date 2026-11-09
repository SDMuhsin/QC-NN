// v3 activation buffers A / B / C: 3 x 8 banks x 512 x 128 b; each bank = two qa_sram 512 x 64 (h = 0: lo half =
// even channel group of the pair, h = 1: hi half), separately enabled (48 macros).  Requesters:
//   ar: array / head reader, one buffer, up to 8 banks in parallel, per-bank half enables (array: both halves,
//       head: one half);
//   pw: PPU writer, one 128-b word (both halves);  pr: PPU residual reader, one 128-b word;
//   h:  host port, one 64-b half.
// As v2: ar, pw and pr are on three different buffers, the host only while idle (bank conflicts checked in sim).
module qa_actmem import qa_pkg::*; (
  input  logic                  clk,
  input  logic [1:0]            ar_buf,
  input  logic [NBANK-1:0]      ar_ce_lo, ar_ce_hi,
  input  logic [NBANK*AAW-1:0]  ar_addr,
  output logic [NBANK*128-1:0]  ar_rdata,
  input  logic                  pw_we,
  input  logic [1:0]            pw_buf,
  input  logic [2:0]            pw_bank,
  input  logic [AAW-1:0]        pw_addr,
  input  logic [127:0]          pw_wdata,
  input  logic                  pr_re,
  input  logic [1:0]            pr_buf,
  input  logic [2:0]            pr_bank,
  input  logic [AAW-1:0]        pr_addr,
  output logic [127:0]          pr_rdata,
  input  logic                  h_ce,
  input  logic                  h_we,
  input  logic [1:0]            h_buf,
  input  logic [2:0]            h_bank,
  input  logic                  h_half,
  input  logic [AAW-1:0]        h_addr,
  input  logic [63:0]           h_wdata,
  output logic [63:0]           h_rdata
);
  logic [63:0] rd [0:2*NBUF*NBANK-1];               // [(b*NBANK + k)*2 + h]
  logic [1:0] ar_buf_q, pr_buf_q, h_buf_q;
  logic [2:0] pr_bank_q, h_bank_q;
  logic h_half_q;

  genvar b, k, h;
  for (b = 0; b < NBUF; b++) begin : g_buf
    for (k = 0; k < NBANK; k++) begin : g_bank
      for (h = 0; h < 2; h++) begin : g_half
        wire s_ar = (h ? ar_ce_hi[k] : ar_ce_lo[k]) && ar_buf == 2'(b);
        wire s_pw = pw_we && pw_buf == 2'(b) && pw_bank == 3'(k);
        wire s_pr = pr_re && pr_buf == 2'(b) && pr_bank == 3'(k);
        wire s_h  = h_ce && h_buf == 2'(b) && h_bank == 3'(k) && h_half == 1'(h);
        logic [AAW-1:0] addr;
        always_comb begin
          addr = '0;
          if (s_ar) addr = ar_addr[k*AAW +: AAW];
          if (s_pw) addr = pw_addr;
          if (s_pr) addr = pr_addr;
          if (s_h)  addr = h_addr;
        end
        qa_sram #(.WORDS(ADEPTH), .BITS(64)) u_ram (
          .clk(clk), .ce(s_ar | s_pw | s_pr | s_h), .we(s_pw | (s_h & h_we)), .addr(addr),
          .wdata(s_pw ? pw_wdata[h*64 +: 64] : h_wdata), .rdata(rd[(b*NBANK+k)*2+h]));
`ifndef SYNTHESIS
        always @(posedge clk)
          if ((32'(s_ar) + 32'(s_pw) + 32'(s_pr) + 32'(s_h)) > 1)
            $error("qa_actmem: bank conflict buffer %0d bank %0d half %0d (ar %b pw %b pr %b host %b)", b, k, h, s_ar, s_pw, s_pr, s_h);
`endif
      end
    end
  end

  always_ff @(posedge clk) begin
    if (|{ar_ce_lo, ar_ce_hi}) ar_buf_q <= ar_buf;
    if (pr_re) begin pr_buf_q <= pr_buf; pr_bank_q <= pr_bank; end
    if (h_ce && !h_we) begin h_buf_q <= h_buf; h_bank_q <= h_bank; h_half_q <= h_half; end
  end
  always_comb begin
    for (int i = 0; i < NBANK; i++)
      ar_rdata[i*128 +: 128] = {rd[(ar_buf_q*NBANK + i)*2 + 1], rd[(ar_buf_q*NBANK + i)*2]};
    pr_rdata = {rd[(pr_buf_q*NBANK + pr_bank_q)*2 + 1], rd[(pr_buf_q*NBANK + pr_bank_q)*2]};
    h_rdata  = rd[(h_buf_q*NBANK + h_bank_q)*2 + h_half_q];
  end
endmodule
