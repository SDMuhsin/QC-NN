// Array step generator (AGU) for one conv pass.  Step order = weight word order: og (outer), tile (8 raster
// output pixels o0..o0+7), kh, kw, cb (inner); one step per cycle, K = k*k*cin8 steps per tile.
// Stage S0 (this module, combinational from the counters): tap offset c(kh, kw, cb) (ARCH "Map layout"), lane
// input index o0 + p + c, bank k serves lane p = (k - c) mod 8 at address in_base + o0/8 + (c >> 3) + (k < c mod 8),
// lane padding mask; weight word address wbase + og*K + kb.  S1 = registered outputs, which drive the act-buffer
// banks and the weight SRAM directly.  The data arrive in S2 (registered macro outputs), are rotated / masked into
// the S3 row registers (qa_xbar) and accumulated by the PEs in S3; a tile's last step captures the accumulators into
// the shadow chains at the end of S3, i.e. 3 cycles after its issue.
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
  output logic [WAW-1:0]       s1_waddr
);
  logic       run;
  logic [7:0] og, cb;
  logic [6:0] tile;
  logic [1:0] kh, kw;
  logic [WAW-1:0] waddr, ogbase;
  logic l2, l3;                                     // last steps in S2 / S3 (S1: s1_vld & s1_last)

  wire [1:0] km1 = k - 2'd1;
  wire [6:0] ntm1 = 7'((32'd1 << (lho + lwo - 4'd3)) - 1);
  wire is_first = kh == 0 && kw == 0 && cb == 0;
  wire is_last  = kh == km1 && kw == km1 && cb == cin8 - 8'd1;
  wire inflight = (s1_vld && s1_last) || l2 || l3;
  wire go = run && !(is_last && (!cap_ok || inflight));

  // ---- S0: tap offset, bank addresses, lane mask --------------------------------------------------------------
  logic signed [21:0] ey, ex, eyh, exh, c, chi, abase;   // all signed arithmetic in explicitly signed 22-b vars
  logic [2:0] clo;
  logic [9:0] o0;
  logic [7:0] lane, ce;
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
    for (int b = 0; b < 8; b++) begin
      ce[b] = lane[3'(b - clo)];
      addr[b*AAW +: AAW] = AAW'(abase + ((3'(b) < clo) ? 22'sd1 : 22'sd0));
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      run <= 1'b0; done <= 1'b0; s1_vld <= 1'b0; s1_first <= 1'b0; s1_last <= 1'b0; s1_ce <= '0;
      l2 <= 1'b0; l3 <= 1'b0; og <= '0; cb <= '0; tile <= '0; kh <= '0; kw <= '0; waddr <= '0; ogbase <= '0;
    end else begin
      l2 <= s1_vld && s1_last;
      l3 <= l2;
      s1_vld <= go;
      s1_ce  <= go ? ce : '0;
      if (go) begin
        s1_first <= is_first; s1_last <= is_last; s1_addr <= addr; s1_rot <= clo; s1_lane <= lane;
        s1_waddr <= waddr;
      end
      if (start) begin
        run <= 1'b1; done <= 1'b0; og <= '0; cb <= '0; tile <= '0; kh <= '0; kw <= '0;
        waddr <= wbase; ogbase <= wbase;
      end else if (go) begin
        waddr <= waddr + 1'b1;
        if (cb != cin8 - 8'd1) cb <= cb + 1'b1;
        else begin
          cb <= '0;
          if (kw != km1) kw <= kw + 1'b1;
          else begin
            kw <= '0;
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
