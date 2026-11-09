// v3 drain controller: shadow-chain drain of TWO columns per read, 64-entry PPU param register file (bias kept in
// 20 b), output / residual address generation, cap_ok for the AGU.  v2 qa_drain with:
// Drain: read r = (p = r / 4, m = r mod 4) takes the heads of columns 2m and 2m + 1 (16 channels = output groups
// og*8 + 2m, + 1 = output PAIR og*4 + m of pixel o0 + p), then both columns shift; 32 reads per tile, one per cycle
// (RELU, RES_ID) or per 2 cycles (RAW16: 2 writes = low / high byte pair planes; RES_R: 2 residual reads), so a tile
// drains in D = 32 / 64 cycles.  A capture is allowed at the edge of the final read.  Params are read from the RF at
// the drain read and travel with the word; the next og's params are loaded after the final read of the previous og
// (64 cycles, 1 word per cycle).
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
  input  logic [8*8*ACC-1:0]   heads,
  output logic                 pm_ce,
  output logic [PAW-1:0]       pm_addr,
  input  logic [PBITS-1:0]     pm_rdata,
  output logic                 q_vld,
  output logic [NL*ACC-1:0]    q_acc,
  output logic [NL*VW-1:0]     q_bias,
  output logic [NL*31-1:0]     q_m0,
  output logic [NL*6-1:0]      q_sh,
  output logic [NL-1:0]        q_d,
  output logic [2:0]           q_obank, q_obank_hi, q_rbank, q_rbank_hi,
  output logic [AAW-1:0]       q_oaddr, q_oaddr_hi, q_raddr, q_raddr_hi,
  input  logic                 ppu_busy,
  output logic                 done,
  output logic                 loading
);
  wire step2 = mode == M_RAW16 || mode == M_RES_R;
  wire [3:0] lhw = lho + lwo;
  wire [6:0] ntm1 = 7'((32'd1 << (lhw - 4'd3)) - 1);
  logic run, fin, sh_full, draining;
  logic [6:0] dj, lcnt, ld_i;
  logic [6:0] d_tile;
  logic [7:0] d_og, rf_og;
  logic rf_valid, ld_v;
  logic [VW-1:0] rf_bias [0:63];
  logic [30:0] rf_m0 [0:63];
  logic [5:0]  rf_sh [0:63];
  logic        rf_d [0:63];

  wire [4:0] w = step2 ? dj[5:1] : dj[4:0];
  wire rd = draining && (!step2 || !dj[0]);
  wire final_rd = rd && w == 5'd31;
  wire [7:0] dlen_m1 = step2 ? 8'd63 : 8'd31;
  wire [1:0] m = w[1:0];
  wire [9:0] o = {d_tile, w[4:2]};
  wire drain_go = run && sh_full && !draining && rf_valid && rf_og == d_og && !loading && !ld_v;
  wire load_go = run && !fin && !(rf_valid && rf_og == d_og) && !loading && !ld_v && !draining;

  // cap_ok: shadow empty, or the running drain's final read is at most 3 cycles away (AGU issue -> capture = 3)
  always_comb begin
    logic [7:0] left;
    left = (step2 ? 8'd62 : 8'd31) - {1'b0, dj};
    cap_ok = !sh_full || (draining && {1'b0, dj} <= (step2 ? 8'd62 : 8'd31) && left <= 8'd3);
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
    logic [7:0] cpo;                                         // output pair og*4 + m
    logic [17:0] io, ih, ro, rh;
    cpo = {d_og[5:0], m};
    if (mode == M_RAW16) begin
      io = index(out_lay, {cpo[6:0], 1'b0}, o, lwo, lhw);    // pair plane 2 cpo: low bytes, 2 cpo + 1: high bytes
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
    q_obank = io[2:0]; q_oaddr = AAW'(out_base + io[17:3]);
    q_obank_hi = ih[2:0]; q_oaddr_hi = AAW'(out_base + ih[17:3]);
    q_rbank = ro[2:0]; q_raddr = AAW'(res_base + ro[17:3]);
    q_rbank_hi = rh[2:0]; q_raddr_hi = AAW'(res_base + rh[17:3]);
    q_vld = rd;
    q_acc = heads[m*16*ACC +: 16*ACC];                       // columns 2m (lanes 0..7), 2m + 1 (lanes 8..15)
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
      rf_valid <= 1'b0; rf_og <= '0; loading <= 1'b0; lcnt <= '0; ld_v <= 1'b0; ld_i <= '0;
    end else begin
      ld_v <= loading; ld_i <= lcnt;
      if (start) begin
        run <= 1'b1; fin <= 1'b0; sh_full <= 1'b0; draining <= 1'b0; dj <= '0; d_tile <= '0; d_og <= '0;
        rf_valid <= 1'b0; loading <= 1'b0;
      end else begin
        if (load_go) begin loading <= 1'b1; lcnt <= '0; rf_og <= d_og; rf_valid <= 1'b0; end
        else if (loading) begin
          lcnt <= lcnt + 1'b1;
          if (lcnt == 7'd63) loading <= 1'b0;
        end
        if (ld_v && ld_i == 7'd63) rf_valid <= 1'b1;
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
  always_ff @(posedge clk) if (ld_v) begin
    rf_bias[ld_i[5:0]] <= pm_rdata[VW-1:0];
    rf_m0[ld_i[5:0]]   <= pm_rdata[62:32];
    rf_sh[ld_i[5:0]]   <= pm_rdata[68:63];
    rf_d[ld_i[5:0]]    <= pm_rdata[69];
  end

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n) begin
    if (cap && sh_full && !final_rd) $error("qa_drain: capture into a full shadow chain");
    if (cap && fin) $error("qa_drain: capture after the last tile");
    if (ld_v && $signed(pm_rdata[31:0]) != $signed(pm_rdata[VW-1:0]))
      $error("qa_drain: bias %0d does not fit %0d b", $signed(pm_rdata[31:0]), VW);
  end
`endif
endmodule
