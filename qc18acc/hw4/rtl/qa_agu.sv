// v4 array step generator: v3 qa_agu (hw3/rtl, v2 comments in hw/rtl/qa_agu.sv apply) on 16-pixel tiles: step order
// og, tile, kh, pair j, kw; tile o0 = 16 * tile; row p reads input index B + p, B = o0 + c(kh, kw, j); bank =
// index mod 16 (rot = B mod 16), address = in_base + (index >> 4) (8 b); 16-slot kw window state (have / held / rd).
// v4 timing (registered macro boundaries): the act-bank requests (ar_ce, ar_addr) leave the AGU combinationally in
// the issue cycle t (S0) and are registered at the macro pins by qa_actmem4; the step control is registered (S1,
// t+1) and travels with the data through qa_xbar (window at t+6); the weight address is registered here (S1) and
// once more in qa_top (t+2) so the code arrives with the window.  Capture (shadow load) at the end of t+6 =
// ISSUE_CAP cycles after the issue: the last step of a tile waits until no other last step is in flight and the
// drain will have read the full shadow chain by then (cap_ok).
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
  output logic [NBANK-1:0]     ar_ce,          // S0: banks read this cycle (combinational)
  output logic [NBANK*AAW-1:0] ar_addr,        // S0: per-bank address
  output logic                 s1_vld, s1_first, s1_last,
  output logic [LNB-1:0]       s1_rot,
  output logic [NROW-1:0]      s1_lane,
  output logic [NROW-1:0]      s1_rd,          // window slots loaded (slot j <- bank (rot + j) mod 16)
  output logic [NBANK-1:0]     s1_ce,          // banks read (= rd rotated)
  output logic                 s1_shift,
  output logic [WAW-1:0]       s1_waddr
);
  localparam int ISSUE_CAP = 6;
  logic       run;
  logic [7:0] og, cb;
  logic [5:0] tile;
  logic [1:0] kh, kw, ki;
  logic [NROW-1:0] have;
  logic [WAW-1:0] waddr, ogbase;
  logic [ISSUE_CAP-1:1] lq;                         // last steps issued 2..ISSUE_CAP cycles ago (1: s1_vld & s1_last)

  wire [1:0] km1 = k - 2'd1;
  wire [5:0] ntm1 = 6'((32'd1 << (lho + lwo - 4'd4)) - 1);
  wire s2k3 = stride == 2'd2 && k == 2'd3;
  assign kw = s2k3 ? ((ki == 2'd1) ? 2'd2 : (ki == 2'd2) ? 2'd1 : 2'd0) : ki;
  wire shift = ki != 2'd0 && (!s2k3 || ki == 2'd1);
  wire [NROW-1:0] held = shift ? {1'b0, have[NROW-1:1]} : '0;
  wire is_first = kh == 0 && ki == 0 && cb == 0;
  wire [7:0] np_m1 = ((cin8 + 8'd1) >> 1) - 8'd1;
  wire is_last  = kh == km1 && ki == km1 && cb == np_m1;
  wire inflight = (s1_vld && s1_last) || |lq;
  wire go = run && !(is_last && (!cap_ok || inflight));

  // ---- S0: tap offset, bank addresses, lane mask --------------------------------------------------------------
  logic signed [21:0] ey, ex, eyh, exh, c, chi, abase;
  logic [LNB-1:0] clo;
  logic [9:0] o0;
  logic [NROW-1:0] lane, rd;
  logic [NBANK-1:0] ce;
  logic [NBANK*AAW-1:0] addr;
  always_comb begin
    ey  = $signed({20'd0, kh}) - $signed({21'd0, k[1]});
    ex  = $signed({20'd0, kw}) - $signed({21'd0, k[1]});
    eyh = ey >>> 1;
    exh = ex >>> 1;
    if (stride == 2'd1)
      c = $signed({14'd0, cb} << (lhi + lwi)) + (ey <<< lwi) + ex;
    else
      c = $signed({14'd0, cb} << (lhi + lwi)) + $signed({20'd0, ey[0], ex[0]} << (lho + lwo)) + (eyh <<< lwo) + exh;
    clo = c[LNB-1:0];
    chi = c >>> LNB;
    o0 = {tile, 4'b0000};
    abase = $signed({14'd0, in_base}) + $signed({16'd0, tile}) + chi;
    for (int p = 0; p < NROW; p++) begin
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
    for (int b = 0; b < NBANK; b++) begin
      ce[b] = rd[LNB'(b - clo)];
      addr[b*AAW +: AAW] = AAW'(abase + ((LNB'(b) < clo) ? 22'sd1 : 22'sd0));
    end
  end
  assign ar_ce   = go ? ce : '0;
  assign ar_addr = addr;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      run <= 1'b0; done <= 1'b0; s1_vld <= 1'b0; s1_first <= 1'b0; s1_last <= 1'b0; lq <= '0;
      og <= '0; cb <= '0; tile <= '0; kh <= '0; ki <= '0; waddr <= '0; ogbase <= '0; have <= '0;
    end else begin
      lq <= {lq[ISSUE_CAP-2:1], s1_vld && s1_last};
      s1_vld <= go;
      if (go) begin
        s1_first <= is_first; s1_last <= is_last; s1_rot <= clo; s1_lane <= lane; s1_ce <= ce;
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
          if (cb != np_m1) cb <= cb + 1'b1;
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
    for (int p = 0; p < NROW; p++) begin
      logic signed [21:0] idx;
      idx = $signed({12'd0, o0}) + p + c;
      if (lane[p] && (idx < 0 || $signed({14'd0, in_base}) + (idx >>> LNB) >= ADEPTH))
        $error("qa_agu: lane %0d input index %0d outside the buffer", p, idx);
    end
  end
`endif
endmodule
