// Array step generator (AGU) for one conv pass.  Step order = weight word order: og (outer), tile (8 raster
// output pixels o0..o0+7), kh, cb, kw (inner; v2), one step per cycle, K = k*k*cin8 steps per tile.  kw runs
// 0, 1, 2 (stride 1) or 0, 2, 1 (stride-2 3x3: kw 0 and 2 read the same odd-x phase plane, offset +1).
// Stage S0 (this module, combinational from the counters): tap offset c(kh, kw, cb) (ARCH "Map layout"), lane
// input index o0 + p + c, slot j of the 8-word kw window = index B + j with B = o0 + c, bank (clo + j) mod 8 at
// address in_base + o0/8 + (c >> 3) + (bank < clo), lane padding mask; weight word address wbase + og*K + kb.
// kw window (v2, ARCH "kw window"): a step is a SHIFT step if it continues a kw run with base B = previous B + 1
// (structural: kw index > 0 for stride 1, kw index 1 (kw = 2 after kw = 0) for stride 2; checked against the index
// in simulation).  have[j] = slot j of the window (qa_xbar) holds the raw word of index B + j:
//   held = shift ? have >> 1 : 0;   rd = lane & ~held (slots read now, one bank each);   have <= held | lane.
// Only rd banks are enabled (normally 1 bank per shift step, the valid lanes on a run's first step).
// S1 = registered outputs, which drive the act-buffer banks and the weight SRAM directly.  The data arrive in S2
// (registered macro outputs), go into the S3 window registers (qa_xbar) and are accumulated by the PEs in S3; a
// tile's last step captures the accumulators into the shadow chains at the end of S3, i.e. 3 cycles after its issue.
// Stall: the last step of a tile is issued only if the shadow chain will be free at its capture (cap_ok from the
// drain controller, which counts down its fixed-rate drain) and no other capture is in flight.
module qa_agu import qa_pkg::*; (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 start,
  input  logic [1:0]           k, stride,
  input  logic [3:0]           lhi, lwi, lho, lwo,
  input  logic [7:0]           hin, win,
  input  logic [7:0]           cin8, cout64,
  input  logic [AAW-1:0]       in_base,
  input  logic [WAW-1:0]       wbase,
  input  logic                 cap_ok,
  output logic                 done,
  output logic                 stall,
  output logic                 s1_vld, s1_first, s1_last,
  output logic [NBANK-1:0]     s1_ce,
  output logic [NBANK*AAW-1:0] s1_addr,
  output logic [2:0]           s1_rot,
  output logic [7:0]           s1_lane,
  output logic [7:0]           s1_rd,          // window slots loaded from the banks (slot j <- bank (rot + j) mod 8)
  output logic                 s1_shift,       // window shifts by one slot before the load
  output logic [WAW-1:0]       s1_waddr
);
  logic       run;
  logic [7:0] og, cb;
  logic [6:0] tile;
  logic [1:0] kh, kw, ki;                           // ki = kw step index, kw = kw_order(ki)
  logic [7:0] have;                                 // window slots holding their word (state after the last issued step)
  logic [WAW-1:0] waddr, ogbase;
  logic l2, l3;                                     // last steps in S2 / S3 (S1: s1_vld & s1_last)

  wire [1:0] km1 = k - 2'd1;
  wire [6:0] ntm1 = 7'((32'd1 << (lho + lwo - 4'd3)) - 1);
  wire s2k3 = stride == 2'd2 && k == 2'd3;
  assign kw = s2k3 ? ((ki == 2'd1) ? 2'd2 : (ki == 2'd2) ? 2'd1 : 2'd0) : ki;
  wire shift = ki != 2'd0 && (!s2k3 || ki == 2'd1);
  wire [7:0] held = shift ? {1'b0, have[7:1]} : 8'd0;
  wire is_first = kh == 0 && ki == 0 && cb == 0;
  wire is_last  = kh == km1 && ki == km1 && cb == cin8 - 8'd1;
  wire inflight = (s1_vld && s1_last) || l2 || l3;
  wire go = run && !(is_last && (!cap_ok || inflight));

  // ---- S0: tap offset, bank addresses, lane mask --------------------------------------------------------------
  logic signed [21:0] ey, ex, eyh, exh, c, chi, abase;   // all signed arithmetic in explicitly signed 22-b vars
  logic [2:0] clo;
  logic [9:0] o0;
  logic [7:0] lane, ce, rd;
  logic [NBANK*AAW-1:0] addr;
  always_comb begin
    ey  = $signed({20'd0, kh}) - $signed({21'd0, k[1]});         // kh - pad, pad = k >> 1
    ex  = $signed({20'd0, kw}) - $signed({21'd0, k[1]});
    eyh = ey >>> 1;
    exh = ex >>> 1;
    if (stride == 2'd1)
      c = $signed({14'd0, cb} << (lhi + lwi)) + (ey <<< lwi) + ex;
    else
      c = $signed({14'd0, cb} << (lhi + lwi)) + $signed({20'd0, ey[0], ex[0]} << (lho + lwo)) + (eyh <<< lwo) + exh;
    clo = c[2:0];
    chi = c >>> 3;
    o0 = {tile, 3'b000};
    abase = $signed({12'd0, in_base}) + $signed({15'd0, tile}) + chi;
    for (int p = 0; p < 8; p++) begin
      logic [9:0] o, yo, xo;
      logic signed [21:0] yi, xi;
      o  = o0 + 10'(p);
      yo = o >> lwo;
      xo = o & ((10'd1 << lwo) - 10'd1);
      yi = $signed({12'd0, yo} << (stride == 2'd2)) + ey;
      xi = $signed({12'd0, xo} << (stride == 2'd2)) + ex;
      lane[p] = yi >= 0 && yi < $signed({14'd0, hin}) && xi >= 0 && xi < $signed({14'd0, win});
    end
    rd = lane & ~held;
    for (int b = 0; b < 8; b++) begin
      ce[b] = rd[3'(b - clo)];
      addr[b*AAW +: AAW] = AAW'(abase + ((3'(b) < clo) ? 22'sd1 : 22'sd0));
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      run <= 1'b0; done <= 1'b0; s1_vld <= 1'b0; s1_first <= 1'b0; s1_last <= 1'b0; s1_ce <= '0;
      l2 <= 1'b0; l3 <= 1'b0; og <= '0; cb <= '0; tile <= '0; kh <= '0; ki <= '0; waddr <= '0; ogbase <= '0;
      have <= '0;
    end else begin
      l2 <= s1_vld && s1_last;
      l3 <= l2;
      s1_vld <= go;
      s1_ce  <= go ? ce : '0;
      if (go) begin
        s1_first <= is_first; s1_last <= is_last; s1_addr <= addr; s1_rot <= clo; s1_lane <= lane;
        s1_waddr <= waddr; s1_rd <= rd; s1_shift <= shift;
        have <= held | lane;
      end
      if (start) begin
        run <= 1'b1; done <= 1'b0; og <= '0; cb <= '0; tile <= '0; kh <= '0; ki <= '0;
        waddr <= wbase; ogbase <= wbase;
      end else if (go) begin
        waddr <= waddr + 1'b1;
        if (ki != km1) ki <= ki + 1'b1;
        else begin
          ki <= '0;
          if (cb != cin8 - 8'd1) cb <= cb + 1'b1;
          else begin
            cb <= '0;
            if (kh != km1) kh <= kh + 1'b1;
            else begin
              kh <= '0;
              if (tile != ntm1) begin tile <= tile + 1'b1; waddr <= ogbase; end
              else begin
                tile <= '0; ogbase <= waddr + 1'b1;
                if (og != cout64 - 8'd1) og <= og + 1'b1;
                else begin run <= 1'b0; done <= 1'b1; end
              end
            end
          end
        end
      end
    end
  end
  assign stall = run && !go;

`ifndef SYNTHESIS
  // the structural shift rule must be the index rule: shift <=> B == previous B + 1 (B = o0 + c, signed)
  logic signed [21:0] bprev;
  logic bprev_ok;
  wire signed [21:0] bcur = $signed({12'd0, o0}) + c;
  always @(posedge clk) begin
    if (!rst_n || start) bprev_ok <= 1'b0;
    else if (go) begin
      if (shift != (bprev_ok && bcur == bprev + 22'sd1))
        $error("qa_agu: shift %0d but base %0d after %0d", shift, bcur, bprev);
      bprev <= bcur; bprev_ok <= 1'b1;
    end
  end
  always @(posedge clk) if (rst_n && go) begin
    for (int p = 0; p < 8; p++) begin
      logic signed [21:0] idx;
      idx = $signed({12'd0, o0}) + p + c;
      if (lane[p] && (idx < 0 || $signed({12'd0, in_base}) + (idx >>> 3) >= ADEPTH))
        $error("qa_agu: lane %0d input index %0d outside the buffer", p, idx);
    end
  end
`endif
endmodule
