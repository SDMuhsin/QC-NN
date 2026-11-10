// v4 drain controller: v3 qa_drain (hw3/rtl) for 16-pixel tiles and 32 PPU lanes (two units of 16).
// Drain read r = 0..31: chain position c = r >> 2, output pair m = r & 3: the heads of columns 2m, 2m + 1 of chain A
// (pixel a = 4 (c >> 1) + (c & 1)) go to PPU unit 0 and those of chain B (pixel b = a + 2) to unit 1, then both
// chains of both columns shift.  32 reads per tile, one per cycle (RELU, RES_ID) or per 2 cycles (RAW16: low / high
// byte pair planes; RES_R: 2 residual reads), so a tile drains in D = 32 / 64 cycles.  Params (64-entry RF, bias 20 b)
// are read at the drain read and travel with both words (same channels); the next og's params are loaded after the
// final read of the previous og (64 words, param SRAM latency MLAT = 3).  cap_ok: the shadow chains are empty, or
// the running drain's final read is at most ISSUE_CAP = 6 cycles away (AGU issue -> capture, qa_agu).
module qa_drain import qa_pkg::*; (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 start,
  input  logic [1:0]           mode,
  input  logic [7:0]           cout64,
  input  logic [3:0]           lho, lwo,
  input  logic                 out_lay, res_lay,
  input  logic [AAW-1:0]       out_base, res_base,
  input  logic [PAW-1:0]       pbase,
  input  logic                 cap,
  output logic                 cap_ok,
  output logic [7:0]           shift,
  input  logic [8*8*ACC-1:0]   heads_a, heads_b,
  output logic                 pm_ce,
  output logic [PAW-1:0]       pm_addr,
  input  logic [PBITS-1:0]     pm_rdata,
  output logic                 q_vld,
  output logic [2*NL*ACC-1:0]  q_acc,          // unit u at [u*NL*ACC +: NL*ACC]
  output logic [NL*VW-1:0]     q_bias,
  output logic [NL*31-1:0]     q_m0,
  output logic [NL*6-1:0]      q_sh,
  output logic [NL-1:0]        q_d,
  output logic [2*LNB-1:0]     q_obank, q_obank_hi, q_rbank, q_rbank_hi,     // unit u at [u*LNB +: LNB]
  output logic [2*AAW-1:0]     q_oaddr, q_oaddr_hi, q_raddr, q_raddr_hi,
  input  logic                 ppu_busy,
  output logic                 done,
  output logic                 loading
);
  localparam int ISSUE_CAP = 6;
  wire step2 = mode == M_RAW16 || mode == M_RES_R;
  wire [3:0] lhw = lho + lwo;
  wire [5:0] ntm1 = 6'((32'd1 << (lhw - 4'd4)) - 1);
  logic run, fin, sh_full, draining;
  logic [6:0] dj, lcnt;
  logic [5:0] d_tile;
  logic [7:0] d_og, rf_og;
  logic rf_valid;
  logic [MLAT:1] ld_v;
  logic [5:0] ld_i [1:MLAT];
  logic [VW-1:0] rf_bias [0:63];
  logic [30:0] rf_m0 [0:63];
  logic [5:0]  rf_sh [0:63];
  logic        rf_d [0:63];

  wire [4:0] w = step2 ? dj[5:1] : dj[4:0];
  wire rd = draining && (!step2 || !dj[0]);
  wire final_rd = rd && w == 5'd31;
  wire [7:0] dlen_m1 = step2 ? 8'd63 : 8'd31;
  wire [1:0] m = w[1:0];
  wire [2:0] cpos = w[4:2];
  wire [3:0] pa = {cpos[2:1], 1'b0, cpos[0]};
  wire [3:0] pb = {cpos[2:1], 1'b1, cpos[0]};
  wire drain_go = run && sh_full && !draining && rf_valid && rf_og == d_og && !loading && !(|ld_v);
  wire load_go = run && !fin && !(rf_valid && rf_og == d_og) && !loading && !(|ld_v) && !draining;

  always_comb begin
    logic [7:0] left;
    left = (step2 ? 8'd62 : 8'd31) - {1'b0, dj};
    cap_ok = !sh_full || (draining && {1'b0, dj} <= (step2 ? 8'd62 : 8'd31) && left <= 8'(ISSUE_CAP));
  end

  function automatic logic [17:0] index(input logic lay, input logic [7:0] cbx, input logic [9:0] oo,
                                        input logic [3:0] lw, input logic [3:0] lhw);
    logic [9:0] yo, xo;
    logic [17:0] pix;
    yo = oo >> lw;
    xo = oo & ((10'd1 << lw) - 10'd1);
    if (lay) pix = (18'({yo[0], xo[0]}) << (lhw - 4'd2)) + (18'(yo >> 1) << (lw - 4'd1)) + 18'(xo >> 1);
    else     pix = 18'(oo);
    index = (18'(cbx) << lhw) + pix;
  endfunction

  always_comb begin
    logic [7:0] cpo;
    logic [17:0] io, ih, ro, rh;
    logic [9:0] o;
    cpo = {d_og[5:0], m};
    for (int u = 0; u < 2; u++) begin
      o = {d_tile, u ? pb : pa};
      if (mode == M_RAW16) begin
        io = index(out_lay, {cpo[6:0], 1'b0}, o, lwo, lhw);
        ih = io + (18'd1 << lhw);
      end else begin
        io = index(out_lay, cpo, o, lwo, lhw);
        ih = io;
      end
      if (mode == M_RES_R) begin
        ro = index(res_lay, {cpo[6:0], 1'b0}, o, lwo, lhw);
        rh = ro + (18'd1 << lhw);
      end else begin
        ro = index(res_lay, cpo, o, lwo, lhw);
        rh = ro;
      end
      q_obank[u*LNB +: LNB] = io[LNB-1:0];    q_oaddr[u*AAW +: AAW] = AAW'(out_base + io[17:LNB]);
      q_obank_hi[u*LNB +: LNB] = ih[LNB-1:0]; q_oaddr_hi[u*AAW +: AAW] = AAW'(out_base + ih[17:LNB]);
      q_rbank[u*LNB +: LNB] = ro[LNB-1:0];    q_raddr[u*AAW +: AAW] = AAW'(res_base + ro[17:LNB]);
      q_rbank_hi[u*LNB +: LNB] = rh[LNB-1:0]; q_raddr_hi[u*AAW +: AAW] = AAW'(res_base + rh[17:LNB]);
    end
    q_vld = rd;
    q_acc = {heads_b[m*16*ACC +: 16*ACC], heads_a[m*16*ACC +: 16*ACC]};
    for (int i = 0; i < NL; i++) begin
      q_bias[i*VW +: VW] = rf_bias[{m, 4'(i)}];
      q_m0[i*31 +: 31]   = rf_m0[{m, 4'(i)}];
      q_sh[i*6 +: 6]     = rf_sh[{m, 4'(i)}];
      q_d[i]             = rf_d[{m, 4'(i)}];
    end
    shift = rd ? (8'd3 << {m, 1'b0}) : 8'd0;
  end

  assign pm_ce   = loading;
  assign pm_addr = PAW'(pbase + {d_og, 6'd0} + lcnt);
  assign done    = run && fin && !draining && !ppu_busy;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      run <= 1'b0; fin <= 1'b0; sh_full <= 1'b0; draining <= 1'b0; dj <= '0; d_tile <= '0; d_og <= '0;
      rf_valid <= 1'b0; rf_og <= '0; loading <= 1'b0; lcnt <= '0; ld_v <= '0;
    end else begin
      ld_v <= {ld_v[MLAT-1:1], loading};
      ld_i[1] <= lcnt[5:0];
      for (int s = 2; s <= MLAT; s++) ld_i[s] <= ld_i[s-1];
      if (start) begin
        run <= 1'b1; fin <= 1'b0; sh_full <= 1'b0; draining <= 1'b0; dj <= '0; d_tile <= '0; d_og <= '0;
        rf_valid <= 1'b0; loading <= 1'b0;
      end else begin
        if (load_go) begin loading <= 1'b1; lcnt <= '0; rf_og <= d_og; rf_valid <= 1'b0; end
        else if (loading) begin
          lcnt <= lcnt + 1'b1;
          if (lcnt == 7'd63) loading <= 1'b0;
        end
        if (ld_v[MLAT] && ld_i[MLAT] == 6'd63) rf_valid <= 1'b1;
        if (drain_go) begin draining <= 1'b1; dj <= '0; end
        else if (draining) begin
          dj <= dj + 1'b1;
          if ({1'b0, dj} == dlen_m1) draining <= 1'b0;
        end
        if (final_rd) begin
          sh_full <= cap;
          if (d_tile != ntm1) d_tile <= d_tile + 1'b1;
          else begin
            d_tile <= '0;
            if (d_og != cout64 - 8'd1) d_og <= d_og + 1'b1;
            else fin <= 1'b1;
          end
        end else if (cap) sh_full <= 1'b1;
      end
    end
  end
  always_ff @(posedge clk) if (ld_v[MLAT]) begin
    rf_bias[ld_i[MLAT]] <= pm_rdata[VW-1:0];
    rf_m0[ld_i[MLAT]]   <= pm_rdata[62:32];
    rf_sh[ld_i[MLAT]]   <= pm_rdata[68:63];
    rf_d[ld_i[MLAT]]    <= pm_rdata[69];
  end

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n) begin
    if (cap && sh_full && !final_rd) $error("qa_drain: capture into a full shadow chain");
    if (cap && fin) $error("qa_drain: capture after the last tile");
    if (ld_v[MLAT] && $signed(pm_rdata[31:0]) != $signed(pm_rdata[VW-1:0]))
      $error("qa_drain: bias %0d does not fit %0d b", $signed(pm_rdata[31:0]), VW);
    if (q_vld && q_obank[0 +: LNB] == q_obank[LNB +: LNB]) $error("qa_drain: both output words in bank %0d", q_obank[0 +: LNB]);
  end
`endif
endmodule
