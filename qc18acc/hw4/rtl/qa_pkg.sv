// QC18-ACC v4 (16 pixel rows, registered macro boundaries) constants (qc18acc/ARCH.md "v4").  Same package name as
// v2 / v3; the v4 file lists (hw4/rtl/qc18acc.f, hw4/tech/qc18acc_tech.f) use this file.
package qa_pkg;
  // activation buffers: 3 buffers (A, B, C) x 16 banks x 256 words x 128 b (one 256 x 128 macro per bank, write
  // mask in 32-b groups: WEN[1:0] = lo 64-b half, WEN[3:2] = hi half)
  localparam int NBUF = 3, NBANK = 16, LNB = 4, ADEPTH = 256, AAW = 8, AW_BITS = 128, AWM = 4;
  localparam int NROW = 16;         // array rows (tile pixels)
  // weight SRAM: two halves (even / odd input group), each WBANKS x WBANK_WORDS x 80 b, read in parallel
  localparam int WBITS = 80, WBANK_WORDS = 4096, WBANKS = 3, WAW = 14;
  localparam int PBITS = 72, PBANK_WORDS = 4096, PBANKS = 2, PAW = 13;
  localparam int DWORDS = 256, DAW = 8;
  // memory read latency (request presented combinationally in cycle t -> macro input flops t+1 -> macro Q t+2 ->
  // macro output register valid t+3); act-buffer array port: + bank-select stage (t+4); residual / host port: +2
  // stages (t+5)
  localparam int MLAT = 3, ALAT = 4, RLAT = 5;
  // PE accumulator, PPU
  localparam int ACC = 20;
  localparam int VW = 20;
  localparam int YW = 20;
  localparam int NL = 16;           // lanes per PPU unit (one 128-b pair word per cycle); v4 has NPPU units
  localparam int NPPU = 2;          // 32 lanes: two pixels per drain read
  localparam logic [1:0] M_RELU = 2'd0, M_RAW16 = 2'd1, M_RES_ID = 2'd2, M_RES_R = 2'd3;
  localparam logic [1:0] T_CONV = 2'd1, T_HEAD = 2'd2;
  // host port: 32-b word address map (addr[23:20] = region); act: [14:13] buffer, [12:9] bank, [8:1] address, [0] half
  localparam logic [3:0] R_CSR = 4'h0, R_PARAM = 4'h1, R_WEIGHT = 4'h2, R_ACT = 4'h3;
  localparam int CSR_CTRL = 'h00, CSR_STATUS = 'h01, CSR_WSTAGE1 = 'h02, CSR_WSTAGE2 = 'h03,
                 CSR_RSTAGE1 = 'h04, CSR_RSTAGE2 = 'h05, CSR_CYC_TOTAL = 'h08, CSR_CYC_BUSY = 'h09,
                 CSR_CYC_STALL = 'h0a, CSR_NPASS = 'h0b, CSR_CYC_PLOAD = 'h0c, CSR_ACT_RD = 'h0d, CSR_PASS0 = 'h20,
                 CSR_LOGIT0 = 'h40, CSR_DESC0 = 'h1000;
  localparam int MAXPASS = 32, MAXCLS = 16;
endpackage
