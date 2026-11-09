// Host port: 32-b word-addressed, memory-mapped (addr[23:20] = region).
//   region 0: CSRs (qa_pkg CSR_*), descriptor RAM at 0x1000 + i
//   region 1: param SRAM word i       region 2: weight SRAM word i
//   region 3: act buffers, addr[14:13] = buffer, [12:10] = bank, [9:0] = address
// Wide words: a write takes bits [31:0] from the write and the upper bits from WSTAGE1 (63:32) / WSTAGE2 (95:64);
// a read returns bits [31:0] and latches the upper bits into RSTAGE1 / RSTAGE2.
// Timing: request registered (h1), memory access in the h1 cycle, read data registered into host_rdata with
// host_rvalid 3 cycles after the request.  One request per cycle, no back-pressure.  Memories may only be
// accessed while the accelerator is idle (CSRs at any time).
module qa_host import qa_pkg::*; (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    host_req,
  input  logic                    host_we,
  input  logic [23:0]             host_addr,
  input  logic [31:0]             host_wdata,
  output logic                    host_rvalid,
  output logic [31:0]             host_rdata,
  // control / status
  output logic                    start,
  input  logic                    busy,
  input  logic                    done,
  // memory ports (h1 cycle)
  output logic                    d_ce, d_we,
  output logic [DAW-1:0]          d_addr,
  output logic [31:0]             d_wdata,
  input  logic [31:0]             d_rdata,
  output logic                    p_ce, p_we,
  output logic [PAW-1:0]          p_addr,
  output logic [PBITS-1:0]        p_wdata,
  input  logic [PBITS-1:0]        p_rdata,
  output logic                    w_ce, w_we,
  output logic [WAW-1:0]          w_addr,
  output logic [WBITS-1:0]        w_wdata,
  input  logic [WBITS-1:0]        w_rdata,
  output logic                    a_ce, a_we,
  output logic [1:0]              a_buf,
  output logic [2:0]              a_bank,
  output logic [AAW-1:0]          a_addr,
  output logic [63:0]             a_wdata,
  input  logic [63:0]             a_rdata,
  // perf / results
  input  logic [31:0]             cyc_total, cyc_busy, cyc_stall, cyc_pload, cnt_ard,
  input  logic [5:0]              npass,
  input  logic [MAXPASS*32-1:0]   cyc_pass,
  input  logic [MAXCLS*32-1:0]    logits
);
  logic        h1, h1_we, h2, h2_rd;
  logic [23:0] h1_addr;
  logic [31:0] h1_wdata, csr_q;
  logic [2:0]  h2_src;                       // 0 CSR, 1 desc, 2 param, 3 weight, 4 act
  logic [31:0] ws1, ws2, rs1, rs2;

  wire [3:0] reg1  = h1_addr[23:20];
  wire is_desc = reg1 == R_CSR && h1_addr[19:12] == 8'h01;
  wire is_csr  = reg1 == R_CSR && h1_addr[19:12] == 8'h00;
  wire [95:0] wide = {ws2, ws1, h1_wdata};

  assign d_ce = h1 && is_desc;               assign d_we = h1_we;
  assign d_addr = h1_addr[DAW-1:0];          assign d_wdata = h1_wdata;
  assign p_ce = h1 && reg1 == R_PARAM;       assign p_we = h1_we;
  assign p_addr = h1_addr[PAW-1:0];          assign p_wdata = wide[PBITS-1:0];
  assign w_ce = h1 && reg1 == R_WEIGHT;      assign w_we = h1_we;
  assign w_addr = h1_addr[WAW-1:0];          assign w_wdata = wide[WBITS-1:0];
  assign a_ce = h1 && reg1 == R_ACT;         assign a_we = h1_we;
  assign a_buf = h1_addr[14:13];             assign a_bank = h1_addr[12:10];
  assign a_addr = h1_addr[9:0];              assign a_wdata = wide[63:0];

  logic [31:0] csr_rd;
  always_comb begin
    logic [11:0] a;
    a = h1_addr[11:0];
    csr_rd = '0;
    if (a == CSR_STATUS) csr_rd = {30'd0, done, busy};
    else if (a == CSR_WSTAGE1) csr_rd = ws1;
    else if (a == CSR_WSTAGE2) csr_rd = ws2;
    else if (a == CSR_RSTAGE1) csr_rd = rs1;
    else if (a == CSR_RSTAGE2) csr_rd = rs2;
    else if (a == CSR_CYC_TOTAL) csr_rd = cyc_total;
    else if (a == CSR_CYC_BUSY) csr_rd = cyc_busy;
    else if (a == CSR_CYC_STALL) csr_rd = cyc_stall;
    else if (a == CSR_CYC_PLOAD) csr_rd = cyc_pload;
    else if (a == CSR_ACT_RD) csr_rd = cnt_ard;
    else if (a == CSR_NPASS) csr_rd = {26'd0, npass};
    else if (a >= CSR_PASS0 && a < CSR_PASS0 + MAXPASS) csr_rd = cyc_pass[(a - CSR_PASS0)*32 +: 32];
    else if (a >= CSR_LOGIT0 && a < CSR_LOGIT0 + MAXCLS) csr_rd = logits[(a - CSR_LOGIT0)*32 +: 32];
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      h1 <= 1'b0; h2 <= 1'b0; h2_rd <= 1'b0; host_rvalid <= 1'b0; start <= 1'b0; ws1 <= '0; ws2 <= '0;
      rs1 <= '0; rs2 <= '0; h2_src <= '0;
    end else begin
      h1 <= host_req; h1_we <= host_we; h1_addr <= host_addr; h1_wdata <= host_wdata;
      start <= 1'b0;
      if (h1 && h1_we && is_csr) begin
        if (h1_addr[11:0] == CSR_CTRL && h1_wdata[0] && !busy) start <= 1'b1;
        if (h1_addr[11:0] == CSR_WSTAGE1) ws1 <= h1_wdata;
        if (h1_addr[11:0] == CSR_WSTAGE2) ws2 <= h1_wdata;
      end
      h2 <= h1 && !h1_we;
      csr_q <= csr_rd;
      h2_src <= is_csr ? 3'd0 : is_desc ? 3'd1 : reg1 == R_PARAM ? 3'd2 : reg1 == R_WEIGHT ? 3'd3 : 3'd4;
      host_rvalid <= h2;
      if (h2) begin
        case (h2_src)
          3'd0: host_rdata <= csr_q;
          3'd1: host_rdata <= d_rdata;
          3'd2: begin host_rdata <= p_rdata[31:0]; rs1 <= p_rdata[63:32]; rs2 <= 32'(p_rdata[PBITS-1:64]); end
          3'd3: begin host_rdata <= w_rdata[31:0]; rs1 <= w_rdata[63:32]; rs2 <= 32'(w_rdata[WBITS-1:64]); end
          default: begin host_rdata <= a_rdata[31:0]; rs1 <= a_rdata[63:32]; rs2 <= '0; end
        endcase
      end
    end
  end
`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n && h1 && !is_csr && busy) $error("qa_host: memory access while busy (addr %h)", h1_addr);
`endif
endmodule
