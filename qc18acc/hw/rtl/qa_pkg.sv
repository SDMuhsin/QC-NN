// QC18-ACC constants (qc18acc/ARCH.md, Appendix "memory images and descriptors").
package qa_pkg;
  // activation buffers: 3 buffers (A, B, C) x 8 banks x 1024 words x 64 b
  localparam int NBUF = 3, NBANK = 8, ADEPTH = 1024, AAW = 10, AW_BITS = 64;
  // weight SRAM: 80-b words, WBANKS x WBANK_WORDS; param SRAM: 72-b words; descriptor RAM: 32-b words
  localparam int WBITS = 80, WBANK_WORDS = 4096, WBANKS = 6, WAW = 15;
  localparam int PBITS = 72, PBANK_WORDS = 4096, PBANKS = 2, PAW = 13;
  localparam int DWORDS = 256, DAW = 8;
  // PE accumulator, PPU
  localparam int ACC = 20;          // signed PE accumulator (ARCH: 2 * 576 * 127 < 2^18; compiler proves < 2^19)
  localparam int YW = 20;           // PPU: requantised value saturated to 20 b signed before residual / clamp
  // pass modes (descriptor word 0 [7:6])
  localparam logic [1:0] M_RELU = 2'd0, M_RAW16 = 2'd1, M_RES_ID = 2'd2, M_RES_R = 2'd3;
  localparam logic [1:0] T_CONV = 2'd1, T_HEAD = 2'd2;
  // host port: 32-b word address map (addr[23:20] = region)
  localparam logic [3:0] R_CSR = 4'h0, R_PARAM = 4'h1, R_WEIGHT = 4'h2, R_ACT = 4'h3;
  // CSR word addresses (region 0; 0x1000..0x10ff = descriptor RAM)
  localparam int CSR_CTRL = 'h00, CSR_STATUS = 'h01, CSR_WSTAGE1 = 'h02, CSR_WSTAGE2 = 'h03,
                 CSR_RSTAGE1 = 'h04, CSR_RSTAGE2 = 'h05, CSR_CYC_TOTAL = 'h08, CSR_CYC_BUSY = 'h09,
                 CSR_CYC_STALL = 'h0a, CSR_NPASS = 'h0b, CSR_CYC_PLOAD = 'h0c, CSR_ACT_RD = 'h0d, CSR_PASS0 = 'h20,
                 CSR_LOGIT0 = 'h40, CSR_DESC0 = 'h1000;
  localparam int MAXPASS = 32, MAXCLS = 16;
endpackage
