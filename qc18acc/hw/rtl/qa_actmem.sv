// Activation buffers A / B / C: 3 x 8 banks x 1024 x 64 b (24 qa_sram).  Four requesters:
//   ar: array / head reader, one buffer, up to 8 banks in parallel (one word per bank)
//   pw: PPU writer, one word;  pr: PPU residual reader, one word;  h: host port, one word.
// The pass schedule (ARCH.md "Buffers and pass schedule") puts ar, pw and pr on three different buffers and the
// host only touches the memories while the accelerator is idle, so a bank never sees two requests in one cycle
// (checked in simulation).  Read data: registered in the macro; the buffer / bank select is registered here.
module qa_actmem import qa_pkg::*; (
  input  logic                  clk,
  input  logic [1:0]            ar_buf,
  input  logic [NBANK-1:0]      ar_ce,
  input  logic [NBANK*AAW-1:0]  ar_addr,
  output logic [NBANK*64-1:0]   ar_rdata,
  input  logic                  pw_we,
  input  logic [1:0]            pw_buf,
  input  logic [2:0]            pw_bank,
  input  logic [AAW-1:0]        pw_addr,
  input  logic [63:0]           pw_wdata,
  input  logic                  pr_re,
  input  logic [1:0]            pr_buf,
  input  logic [2:0]            pr_bank,
  input  logic [AAW-1:0]        pr_addr,
  output logic [63:0]           pr_rdata,
  input  logic                  h_ce,
  input  logic                  h_we,
  input  logic [1:0]            h_buf,
  input  logic [2:0]            h_bank,
  input  logic [AAW-1:0]        h_addr,
  input  logic [63:0]           h_wdata,
  output logic [63:0]           h_rdata
);
  logic [63:0] rd [0:NBUF*NBANK-1];
  logic [1:0] ar_buf_q, pr_buf_q, h_buf_q;
  logic [2:0] pr_bank_q, h_bank_q;

  genvar b, k;
  for (b = 0; b < NBUF; b++) begin : g_buf
    for (k = 0; k < NBANK; k++) begin : g_bank
      wire s_ar = ar_ce[k] && ar_buf == 2'(b);
      wire s_pw = pw_we && pw_buf == 2'(b) && pw_bank == 3'(k);
      wire s_pr = pr_re && pr_buf == 2'(b) && pr_bank == 3'(k);
      wire s_h  = h_ce && h_buf == 2'(b) && h_bank == 3'(k);
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
        .wdata(s_pw ? pw_wdata : h_wdata), .rdata(rd[b*NBANK+k]));
`ifndef SYNTHESIS
      always @(posedge clk)
        if ((32'(s_ar) + 32'(s_pw) + 32'(s_pr) + 32'(s_h)) > 1)
          $error("qa_actmem: bank conflict buffer %0d bank %0d (ar %b pw %b pr %b host %b)", b, k, s_ar, s_pw, s_pr, s_h);
`endif
    end
  end

  always_ff @(posedge clk) begin
    if (|ar_ce) ar_buf_q <= ar_buf;
    if (pr_re) begin pr_buf_q <= pr_buf; pr_bank_q <= pr_bank; end
    if (h_ce && !h_we) begin h_buf_q <= h_buf; h_bank_q <= h_bank; end
  end
  always_comb begin
    for (int i = 0; i < NBANK; i++) ar_rdata[i*64 +: 64] = rd[ar_buf_q*NBANK + i];
    pr_rdata = rd[pr_buf_q*NBANK + pr_bank_q];
    h_rdata  = rd[h_buf_q*NBANK + h_bank_q];
  end
endmodule
