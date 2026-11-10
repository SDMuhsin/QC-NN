// v4 head: global average pool + FC (ARCH "Head", Appendix head descriptor; v3 hw3/rtl/qa_head.sv), re-timed for the
// registered memory boundaries (act array port ALAT = 4, weight / param MLAT = 3) and with the FC dot pipelined
// (ARCH v4: no path from a macro Q to the dot output in one cycle; here the dot starts from the weight macro's output
// register and is split into a product stage and a sum stage).
//   bias:  logit[j] = FC bias (param SRAM, pbase + j)
//   pool:  per channel group cb: read the H*W/16 rows of 16 pixel words (all 16 banks), half cb[0] of pair plane
//          cb >> 1, sum per lane, requant + clamp [0, 127] through PPU unit 0 (bias 0, pool m0 / sh) -> p[8]
//   FC:    logit[j] += sum_lane W8[j, 8 cb + lane] * p[lane], FC word = weight SRAM (even half) wbase + cb * ncls + j
// Pool results go through a 2-entry FIFO so the pool of groups cb + 1, cb + 2 runs while the FC of group cb reads
// its ncls weight words (1 per cycle).
//   FC pipeline: f0 request (wm_ce) -> f3 weight word (output register) -> f4 products -> f5 dot -> logit update.
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
  output logic [NBANK-1:0]     ar_ce,
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
  logic [MLAT:1] b_v;
  logic [3:0] b_j [1:MLAT];
  logic pool_iss;
  logic [ALAT:1] pv, pfirst, plast, phi;              // pool issue pipeline: valid / first row / last row / half
  logic pd_v, pd_first, pd_last;
  logic [NBANK*64-1:0] pd;
  logic [8*ACC-1:0] psum;
  logic [1:0] npend, fcnt;                            // groups issued and not yet taken by the FC; FIFO count
  logic [63:0] fifo [0:1];
  logic fc_busy;
  logic [63:0] pfc;
  logic [5:1] fv;
  logic [3:0] fjd [1:5];
  logic [63:0] pfd [1:3];
  logic signed [15:0] prod [0:7];
  logic signed [31:0] dot5;
  logic [WAW-1:0] fwa;

  wire [6:0] rows_m1 = 7'((32'd1 << (lhw - 4'd4)) - 1);

  assign pm_ce   = st == H_BIAS;
  assign pm_addr = PAW'(pbase + bcnt);
  assign ar_ce   = pool_iss ? '1 : '0;
  always_comb for (int k = 0; k < NBANK; k++) ar_addr[k*AAW +: AAW] = AAW'(in_base + ((pcb >> 1) << (lhw - 4'd4)) + pr);
  assign wm_ce   = fc_busy;
  assign wm_addr = fwa;
  assign done    = st == H_FIN;

  // lane sums of the 16 pixel words of one row (pd, valid the cycle after the bank-select data), accumulated over rows
  logic [8*ACC-1:0] psum_n;
  always_comb begin
    for (int l = 0; l < 8; l++) begin
      logic signed [ACC-1:0] t;
      t = pd_first ? '0 : $signed(psum[l*ACC +: ACC]);
      for (int k = 0; k < NBANK; k++) t = t + $signed(pd[k*64 + l*8 +: 8]);
      psum_n[l*ACC +: ACC] = t;
    end
  end

  wire pool_go = st == H_RUN && !pool_iss && pcb != cin8 && !(|b_v) && npend != 2'd2;
  wire fc_go = !fc_busy && fcnt != 2'd0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= H_IDLE; bcnt <= '0; pcb <= '0; fcb <= '0; fj <= '0; pr <= '0; b_v <= '0; pool_iss <= 1'b0;
      pv <= '0; pd_v <= 1'b0; fc_busy <= 1'b0; fv <= '0; ppu_vld <= 1'b0; npend <= '0; fcnt <= '0;
    end else begin
      b_v <= {b_v[MLAT-1:1], pm_ce};
      b_j[1] <= bcnt[3:0];
      for (int s = 2; s <= MLAT; s++) b_j[s] <= b_j[s-1];
      pv <= {pv[ALAT-1:1], pool_iss};
      pfirst <= {pfirst[ALAT-1:1], pool_iss && pr == 0};
      plast <= {plast[ALAT-1:1], pool_iss && pr == rows_m1};
      phi <= {phi[ALAT-1:1], pcb[0]};
      pd_v <= pv[ALAT]; pd_first <= pfirst[ALAT]; pd_last <= plast[ALAT];
      ppu_vld <= pd_v && pd_last;
      fv <= {fv[4:1], fc_busy};
      fjd[1] <= fj[3:0];
      for (int s = 2; s <= 5; s++) fjd[s] <= fjd[s-1];
      // pooled-result FIFO (PPU unit 0 output) and pending-group count
      if (hp_vld) fifo[fcnt[0] & ~fc_go] <= hp;       // push at the tail (after a same-cycle pop: slot 0)
      if (fc_go) fifo[0] <= (hp_vld && fcnt == 2'd1) ? hp : fifo[1];
      fcnt <= fcnt + 2'(hp_vld) - 2'(fc_go);
      npend <= npend + 2'(pool_go) - 2'(fc_go);
      case (st)
        H_IDLE: if (start) begin st <= H_BIAS; bcnt <= '0; pcb <= '0; fcb <= '0; npend <= '0; fcnt <= '0; end
        H_BIAS: begin
          bcnt <= bcnt + 1'b1;
          if (bcnt == ncls - 8'd1) st <= H_RUN;
        end
        H_RUN: begin
          if (pool_go) begin pool_iss <= 1'b1; pr <= '0; end
          else if (pool_iss) begin
            if (pr == rows_m1) begin pool_iss <= 1'b0; pcb <= pcb + 1'b1; end
            else pr <= pr + 1'b1;
          end
          if (fc_go) begin
            pfc <= fifo[0]; fc_busy <= 1'b1; fj <= '0; fwa <= WAW'(wbase + fcb * ncls);
          end else if (fc_busy) begin
            fwa <= fwa + 1'b1; fj <= fj + 1'b1;
            if (fj == ncls - 8'd1) begin fc_busy <= 1'b0; fcb <= fcb + 1'b1; end
          end
          if (fcb == cin8 && !fc_busy && !(|fv)) st <= H_FIN;
        end
        H_FIN: st <= H_IDLE;
        default: st <= H_IDLE;
      endcase
    end
  end
  always_ff @(posedge clk) begin
    if (pv[ALAT])
      for (int k = 0; k < NBANK; k++) pd[k*64 +: 64] <= phi[ALAT] ? ar_rdata[k*128+64 +: 64] : ar_rdata[k*128 +: 64];
    if (pd_v) psum <= psum_n;
    if (pd_v && pd_last) ppu_acc <= psum_n;
    // FC: p travels with the request (pfd), products at f4, dot at f5, logit update at the end of f5
    pfd[1] <= pfc; pfd[2] <= pfd[1]; pfd[3] <= pfd[2];
    if (fv[3]) for (int l = 0; l < 8; l++) prod[l] <= $signed(wm_rdata[l*8 +: 8]) * $signed({1'b0, pfd[3][l*8 +: 8]});
    if (fv[4]) dot5 <= ((32'(prod[0]) + 32'(prod[1])) + (32'(prod[2]) + 32'(prod[3]))) +
                       ((32'(prod[4]) + 32'(prod[5])) + (32'(prod[6]) + 32'(prod[7])));
    if (b_v[MLAT]) logits[b_j[MLAT]*32 +: 32] <= pm_rdata[31:0];
    if (fv[5]) logits[fjd[5]*32 +: 32] <= logits[fjd[5]*32 +: 32] + dot5;
  end
`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n && start && (ncls > MAXCLS || lhw < 4)) $error("qa_head: unsupported head descriptor");
  always @(posedge clk) if (rst_n && hp_vld && fcnt == 2'd2 && !fc_go) $error("qa_head: pool FIFO overflow");
`endif
endmodule
