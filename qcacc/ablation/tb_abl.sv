// Testbench of one ablation core (AblGemm_<variant>, RTL or DC netlist): streams one vector file of
// qcacc/ablation/vectors.py at full rate (A / B / C always valid, D always ready, as a streamer without stalls)
// and checks every D tile.  Inputs change at 20 % of the period after the rising edge (the SDC input delay),
// handshakes are sampled at 90 %.  /tb_abl/busy = the DUT's io_busy_o (SAIF window, abl.do).
//   +define+DUT=AblGemm_<v> +define+BW=<B bits>   plusargs: +VEC=<file> +PERIOD_PS=<n> (2800)
// Prints ABL_RESULT <PASS|FAIL> tiles <n> bad <n> busy_cycles <n> fires <n>.
`timescale 1ns / 1ps
module tb_abl;
  localparam int MAXF = 8192, MAXT = 1024;
  int period_ps = 2800;
  logic clock = 0, reset = 1;
  logic [511:0] a_mem[MAXF];
  logic [`BW-1:0] b_mem[MAXF];
  logic [2047:0] c_mem[MAXT], d_mem[MAXT];
  int K, N, M, SC, T;

  logic ctrl_ready, ctrl_valid = 0;
  logic a_ready, a_valid = 0, b_ready, b_valid = 0, c_ready, c_valid = 0, d_ready = 0, d_valid;
  logic [511:0] a_bits = '0;
  logic [`BW-1:0] b_bits = '0;
  logic [2047:0] c_bits = '0, d_bits;
  logic busy;
  logic [31:0] perf;
  logic [31:0] cfg_k = 0, cfg_n = 0, cfg_m = 0, cfg_sc = 0;

  `DUT dut (
      .clock(clock), .reset(reset),
      .io_ctrl_ready(ctrl_ready), .io_ctrl_valid(ctrl_valid),
      .io_ctrl_bits_K_i(cfg_k), .io_ctrl_bits_N_i(cfg_n), .io_ctrl_bits_M_i(cfg_m),
      .io_ctrl_bits_subtraction_constant_i(cfg_sc),
      .io_data_a_i_ready(a_ready), .io_data_a_i_valid(a_valid), .io_data_a_i_bits(a_bits),
      .io_data_b_i_ready(b_ready), .io_data_b_i_valid(b_valid), .io_data_b_i_bits(b_bits),
      .io_data_c_i_ready(c_ready), .io_data_c_i_valid(c_valid), .io_data_c_i_bits(c_bits),
      .io_data_d_o_ready(d_ready), .io_data_d_o_valid(d_valid), .io_data_d_o_bits(d_bits),
      .io_busy_o(busy), .io_performance_counter(perf));

  always #(period_ps / 2000.0) clock = ~clock;

  task automatic load(string fn);
    int fd, r;
    logic [511:0] a, b;
    fd = $fopen(fn, "r");
    if (fd == 0) $fatal(1, "cannot open %s", fn);
    r = $fscanf(fd, "%d %d %d %d %d\n", K, N, M, SC, T);
    if (T > MAXT || T * K > MAXF) $fatal(1, "vector file too large");
    for (int t = 0; t < T; t++) begin
      for (int k = 0; k < K; k++) begin
        r = $fscanf(fd, "%h %h\n", a, b);
        a_mem[t * K + k] = a;
        b_mem[t * K + k] = b[`BW-1:0];
      end
      r = $fscanf(fd, "%h\n", c_mem[t]);
      r = $fscanf(fd, "%h\n", d_mem[t]);
    end
    $fclose(fd);
  endtask

  initial begin
    string fn;
    int ia = 0, ib = 0, ic = 0, id = 0, bad = 0, cyc = 0, busy_cyc = 0;
    bit fa, fb, fc, fd;
    if (!$value$plusargs("VEC=%s", fn)) $fatal(1, "+VEC=<file> missing");
    void'($value$plusargs("PERIOD_PS=%d", period_ps));
    load(fn);
    $display("ABL_INFO vec %s K %0d N %0d M %0d sc %0d tiles %0d period_ps %0d", fn, K, N, M, SC, T, period_ps);
    repeat (4) @(posedge clock);
    #(period_ps * 0.0002) reset = 0;
    repeat (2) @(posedge clock);
    // configure
    #(period_ps * 0.0002);
    cfg_k = K; cfg_n = N; cfg_m = M; cfg_sc = SC; ctrl_valid = 1;
    @(posedge clock);
    #(period_ps * 0.0002) ctrl_valid = 0;
    a_valid = 1; b_valid = 1; c_valid = 1; d_ready = 1;
    a_bits = a_mem[0]; b_bits = b_mem[0]; c_bits = c_mem[0];
    while (id < T && cyc < 20 * T * (K + 1) + 1000) begin
      #(period_ps * 0.0007);                 // 90 % of the period: sample the handshakes
      fa = a_valid && a_ready; fb = b_valid && b_ready; fc = c_valid && c_ready; fd = d_valid && d_ready;
      if (busy) busy_cyc++;
      if (fd) begin
        if (d_bits !== d_mem[id]) begin
          bad++;
          if (bad <= 3) $display("ABL_MISMATCH tile %0d got %h exp %h", id, d_bits[63:0], d_mem[id][63:0]);
        end
        id++;
      end
      @(posedge clock);
      cyc++;
      #(period_ps * 0.0002);                 // 20 %: next inputs
      if (fa) begin ia++; if (ia < T * K) a_bits = a_mem[ia]; else a_valid = 0; end
      if (fb) begin ib++; if (ib < T * K) b_bits = b_mem[ib]; else b_valid = 0; end
      if (fc) begin ic++; if (ic < T) c_bits = c_mem[ic]; else c_valid = 0; end
    end
    repeat (4) @(posedge clock);
    $display("ABL_RESULT %s tiles %0d/%0d bad %0d busy_cycles %0d perf %0d fires %0d ideal %0d",
             (id == T && bad == 0 && ia == T * K && !busy) ? "PASS" : "FAIL", id, T, bad, busy_cyc, perf, ia,
             T * (K + 1));
    $finish;
  end
endmodule
