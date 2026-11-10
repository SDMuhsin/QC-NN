// Testbench of one ablation array top (qab_top_<v>, RTL or DC netlist): streams one vector file of
// qc18acc/ablation/vectors.py back to back (one step per cycle, as the v2 sequencer inside a pass), drains every
// tile's shadow registers through the column heads (7 shifts right after the capture) and checks all 64 heads x 8
// rows of every tile against the numpy reference.
//   +define+TOP=qab_top_<v> +define+WB=<weight bits per column> +define+ACC=<acc bits> [+define+QAB_SAIF (VCS)]
//   [+define+XB=1024: the Kb = 2 tops qab3_top_<v> (vectors3.py, 8 x 128-b rows); default 512]
//   plusargs: +VEC=<file> +PERIOD_PS=<n> (2500) +SAIF=<file>
// Inputs are driven at the rising edge (the SDF view adds the SDC input delay, flow/tsmc65/sim/sdf_idealclk.py),
// heads are sampled at the falling edge.  Pipeline: step n driven in cycle n -> input register -> the PE computes
// it in cycle n + 1; a tile's last step n captures at the edge ending cycle n + 1, so drain row r is at the heads in
// cycle n + 2 + r (shift driven in cycles n + 1 .. n + 7).  SAIF window: cycles 1 .. NS (the PE busy cycles).
// Prints QAB_RESULT <PASS|FAIL> tiles <n> rows_checked <n> bad <n> steps <n>.
`timescale 1ns / 1ps
`ifndef XB
`define XB 512
`endif
module tb_qab;
  localparam int MAXS = 2304, MAXT = 64;
  int period_ps = 2500;
  logic clk = 0, rst_n = 0;
  logic in_vld = 0, in_first = 0, in_last = 0;
  logic [7:0] in_shift = 0;
  logic [`XB-1:0] in_x = '0;
  logic [8*`WB-1:0] in_w = '0;
  logic [64*`ACC-1:0] heads;
  logic [`XB-1:0] x_mem[MAXS];
  logic [8*`WB-1:0] w_mem[MAXS];
  logic [64*`ACC-1:0] e_mem[MAXT*8];
  int K, T, WBf, ACCf, NS;

  `TOP dut (.clk(clk), .rst_n(rst_n), .in_vld(in_vld), .in_first(in_first), .in_last(in_last), .in_shift(in_shift),
            .in_x(in_x), .in_w(in_w), .heads(heads));

  always #(period_ps / 2000.0) clk = ~clk;

  task automatic load(string fn);
    int fd, r;
    fd = $fopen(fn, "r");
    if (fd == 0) $fatal(1, "cannot open %s", fn);
    r = $fscanf(fd, "%d %d %d %d %d\n", K, T, WBf, ACCf, NS);
    if (WBf != `WB || ACCf != `ACC || NS != T * K || NS > MAXS || T > MAXT) $fatal(1, "vector file / build mismatch");
    for (int n = 0; n < NS; n++) r = $fscanf(fd, "%h %h\n", x_mem[n], w_mem[n]);
    for (int n = 0; n < 8 * T; n++) r = $fscanf(fd, "%h\n", e_mem[n]);
    $fclose(fd);
  endtask

`ifdef QAB_SAIF
  string saif_fn;
`endif

  int c = -1, bad = 0, rows = 0;
  bit run = 0, fin = 0;
  // cycle c starts at a rising edge: drive step c (registered by the DUT at the next edge), drain shifts
  always @(posedge clk) if (run && !fin) begin
    logic sh;
    int nl;
    c = c + 1;
    if (c < NS) begin
      in_vld <= 1; in_first <= (c % K == 0); in_last <= (c % K == K - 1); in_x <= x_mem[c]; in_w <= w_mem[c];
    end else in_vld <= 0;
    sh = 0;
    for (int t = 0; t < T; t++) begin nl = t * K + K - 1; if (c >= nl + 1 && c <= nl + 7) sh = 1; end
    in_shift <= {8{sh}};
`ifdef QAB_SAIF
    if (c == 1) begin
      if (!$value$plusargs("SAIF=%s", saif_fn)) saif_fn = "qab.saif";
      $set_gate_level_monitoring("on");
      $set_toggle_region(tb_qab.dut);
      $toggle_start;
    end
    if (c == NS + 1) begin
      $toggle_stop;
      $toggle_report(saif_fn, 1.0e-9, "tb_qab.dut");
      $display("QAB_SAIF %0s cycles 1..%0d (%0d)", saif_fn, NS, NS);
    end
`endif
    if (c == NS + 16) fin = 1;
  end
  // drain row r of tile t is at the heads in cycle (t K + K - 1) + 2 + r
  always @(negedge clk) if (run && !fin && c >= 0) begin
    int r;
    for (int t = 0; t < T; t++) begin
      r = c - (t * K + K - 1) - 2;
      if (r >= 0 && r < 8) begin
        rows++;
        if (heads !== e_mem[t * 8 + r]) begin
          bad++;
          if (bad <= 3) $display("QAB_MISMATCH tile %0d row %0d got %h exp %h", t, r, heads[63:0], e_mem[t * 8 + r][63:0]);
        end
      end
    end
  end

  initial begin
    string fn;
    if (!$value$plusargs("VEC=%s", fn)) $fatal(1, "+VEC=<file> missing");
    void'($value$plusargs("PERIOD_PS=%d", period_ps));
    load(fn);
    $display("QAB_INFO vec %s K %0d tiles %0d steps %0d period_ps %0d", fn, K, T, NS, period_ps);
    repeat (4) @(posedge clk);
    @(negedge clk) rst_n = 1;
    repeat (2) @(posedge clk);
    @(negedge clk) run = 1;
    wait (fin);
    @(negedge clk);
    $display("QAB_RESULT %s tiles %0d rows_checked %0d bad %0d steps %0d", (bad == 0 && rows == 8 * T) ? "PASS" : "FAIL",
             T, rows, bad, NS);
    $finish;
  end
endmodule
