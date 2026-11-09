// Head: global average pool + FC (ARCH "Head", Appendix head descriptor).
//   bias:  logit[j] = FC bias (param SRAM, pbase + j)
//   pool:  per channel group cb: read the H*W/8 rows of 8 pixel words (all 8 banks in parallel), sum per lane,
//          requant + clamp [0, 127] through the PPU (bias 0, m0 / sh = pool m0 / sh)  ->  p[8]
//   FC:    logit[j] += sum_lane W8[j, 8 cb + lane] * p[lane], FC word = weight SRAM wbase + cb * ncls + j
// The pool of group cb + 1 runs while the FC of group cb reads its ncls weight words (1 per cycle).
module qa_head import qa_pkg::*; (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 start,
  input  logic [3:0]           lhw,             // log2(H * W)
  input  logic [AAW-1:0]       in_base,
  input  logic [7:0]           cin8,
  input  logic [7:0]           ncls,
  input  logic [WAW-1:0]       wbase,
  input  logic [PAW-1:0]       pbase,
  output logic [NBANK-1:0]     ar_ce_lo, ar_ce_hi,
  output logic [NBANK*AAW-1:0] ar_addr,
  input  logic [NBANK*128-1:0] ar_rdata,
  output logic                 wm_ce,
  output logic [WAW-1:0]       wm_addr,
  input  logic [WBITS-1:0]     wm_rdata,
  output logic                 pm_ce,
  output logic [PAW-1:0]       pm_addr,
  input  logic [PBITS-1:0]     pm_rdata,
  output logic                 ppu_vld,
  output logic [8*ACC-1:0]     ppu_acc,
  input  logic                 hp_vld,
  input  logic [63:0]          hp,
  output logic [MAXCLS*32-1:0] logits,
  output logic                 done
);
  typedef enum logic [1:0] {H_IDLE, H_BIAS, H_RUN, H_FIN} st_t;
  st_t st;
  logic [7:0] bcnt, pcb, fcb, fj;
  logic [6:0] pr;
  logic b_v;
  logic [3:0] b_j;
  logic pool_busy, pool_iss, pd_v, pd_first, pd_last, pd_v2, pd_first2, pd_last2;
  logic pbuf_v, fc_busy, f1_v, f2_v;
  logic [3:0] f1_j, f2_j;
  logic [63:0] pbuf, pfc;
  logic [NBANK*64-1:0] pd;
  logic [8*ACC-1:0] psum;
  logic signed [31:0] dot2;
  logic [WAW-1:0] fwa;

  wire [6:0] rows_m1 = 7'((32'd1 << (lhw - 4'd3)) - 1);

  assign pm_ce   = st == H_BIAS;
  assign pm_addr = PAW'(pbase + bcnt);
  assign ar_ce_lo = (pool_iss && !pcb[0]) ? '1 : '0;
  assign ar_ce_hi = (pool_iss && pcb[0]) ? '1 : '0;
  always_comb for (int k = 0; k < 8; k++) ar_addr[k*AAW +: AAW] = AAW'(in_base + ((pcb >> 1) << (lhw - 4'd3)) + pr);
  logic iss_hi;                                     // half of the words arriving in the pd_v cycle
  logic [NBANK*64-1:0] ar_half;
  always_comb for (int k = 0; k < 8; k++) ar_half[k*64 +: 64] = iss_hi ? ar_rdata[k*128+64 +: 64] : ar_rdata[k*128 +: 64];
  assign wm_ce   = fc_busy;
  assign wm_addr = fwa;
  assign done    = st == H_FIN;

  // lane sums of the 8 pixel words of one row, accumulated over the rows
  logic [8*ACC-1:0] psum_n;
  always_comb begin
    for (int l = 0; l < 8; l++) begin
      logic signed [ACC-1:0] t;
      t = pd_first2 ? '0 : $signed(psum[l*ACC +: ACC]);
      for (int k = 0; k < 8; k++) t = t + $signed(pd[k*64 + l*8 +: 8]);
      psum_n[l*ACC +: ACC] = t;
    end
  end
  // FC dot product of one weight word with p
  logic signed [31:0] dot;
  always_comb begin
    dot = '0;
    for (int l = 0; l < 8; l++) dot = dot + $signed(wm_rdata[l*8 +: 8]) * $signed({1'b0, pfc[l*8 +: 8]});
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= H_IDLE; bcnt <= '0; pcb <= '0; fcb <= '0; fj <= '0; pr <= '0; b_v <= 1'b0; pool_busy <= 1'b0;
      pool_iss <= 1'b0; pd_v <= 1'b0; pd_v2 <= 1'b0; pbuf_v <= 1'b0; fc_busy <= 1'b0; f1_v <= 1'b0; f2_v <= 1'b0;
      ppu_vld <= 1'b0; pd_first <= 1'b0; pd_last <= 1'b0; pd_first2 <= 1'b0; pd_last2 <= 1'b0;
    end else begin
      b_v <= pm_ce; b_j <= bcnt[3:0];
      ppu_vld <= 1'b0;
      // pipeline: issue (pool_iss) -> macro output (pd_v) -> registered rows (pd_v2) -> psum
      iss_hi <= pcb[0];
      pd_v <= pool_iss; pd_first <= pool_iss && pr == 0; pd_last <= pool_iss && pr == rows_m1;
      pd_v2 <= pd_v; pd_first2 <= pd_first; pd_last2 <= pd_last;
      f1_v <= fc_busy; f1_j <= fj[3:0];
      f2_v <= f1_v; f2_j <= f1_j; dot2 <= dot;
      case (st)
        H_IDLE: if (start) begin st <= H_BIAS; bcnt <= '0; pcb <= '0; fcb <= '0; pbuf_v <= 1'b0; end
        H_BIAS: begin
          bcnt <= bcnt + 1'b1;
          if (bcnt == ncls - 8'd1) st <= H_RUN;
        end
        H_RUN: begin
          // pool engine
          if (!pool_busy && !pbuf_v && pcb != cin8 && !b_v) begin pool_busy <= 1'b1; pool_iss <= 1'b1; pr <= '0; end
          else if (pool_iss) begin
            if (pr == rows_m1) begin pool_iss <= 1'b0; pcb <= pcb + 1'b1; end
            else pr <= pr + 1'b1;
          end
          if (pd_v2 && pd_last2) ppu_vld <= 1'b1;
          if (hp_vld) begin pbuf <= hp; pbuf_v <= 1'b1; pool_busy <= 1'b0; end
          // FC engine
          if (!fc_busy && pbuf_v) begin
            pfc <= pbuf; pbuf_v <= 1'b0; fc_busy <= 1'b1; fj <= '0; fwa <= WAW'(wbase + fcb * ncls);
          end else if (fc_busy) begin
            fwa <= fwa + 1'b1; fj <= fj + 1'b1;
            if (fj == ncls - 8'd1) begin fc_busy <= 1'b0; fcb <= fcb + 1'b1; end
          end
          if (fcb == cin8 && !fc_busy && !f1_v && !f2_v) st <= H_FIN;
        end
        H_FIN: st <= H_IDLE;
        default: st <= H_IDLE;
      endcase
    end
  end
  always_ff @(posedge clk) begin
    if (pd_v) pd <= ar_half;
    if (pd_v2) psum <= psum_n;
    if (pd_v2 && pd_last2) ppu_acc <= psum_n;
    if (b_v) logits[b_j*32 +: 32] <= pm_rdata[31:0];
    if (f2_v) logits[f2_j*32 +: 32] <= logits[f2_j*32 +: 32] + dot2;
  end
`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n && start && (ncls > MAXCLS || lhw < 3)) $error("qa_head: unsupported head descriptor");
`endif
endmodule
