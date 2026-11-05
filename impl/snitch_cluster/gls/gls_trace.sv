// Retire trace + X check for the Snitch cluster, from the I-cache fetch ports only, so the same
// monitor runs on the RTL and on the DC netlist (where the cores are ungrouped and the RTL tracer
// does not exist). Loaded as a second top level next to tb_bin.
//
// Retire rule (snitch.sv): the core holds pc_q while it stalls and advances it when it issues, so
// the instruction at pc retires in the last cycle in which it is fetched (valid & ready) before pc
// changes. Validated on the RTL against the upstream tracer (gls_summary.py --rtl-dasm).
// Each event is written as "<time ps> <pc> <insn>", time = the clock edge that ends the cycle, as
// in the upstream trace. Values are sampled 20 ps before that edge (settled in zd and SDF runs).
//
// X check: from 5 cycles after reset, every fetch handshake must be 0/1, and so must the pc of a
// valid fetch, the instruction of an accepted one and the cluster's AXI handshakes / valid
// addresses. A violation is a $error (GLS_X), counted in the end-of-run line GLS_TRACE.
`ifdef GLS
  `define HIVE tb_bin.i_dut.i_snitch_cluster.i_cluster.gen_hive_0__i_snitch_hive.i_snitch_icache
`else
  `define HIVE tb_bin.i_dut.i_snitch_cluster.i_cluster.gen_hive[0].i_snitch_hive.i_snitch_icache
`endif
`define TH tb_bin.i_dut

module gls_trace #(
  parameter int TCK_PS = 1000   // clock period of tb_bin (TCK)
);
  localparam int N = 9, SMP_PS = TCK_PS - 20;
  wire clk = tb_bin.clk_i, rst_n = tb_bin.rst_ni;
  wire [N*48-1:0] addr = `HIVE .inst_addr_i;
  wire [N*32-1:0] data = `HIVE .inst_data_o;
  wire [N-1:0] valid = `HIVE .inst_valid_i, ready = `HIVE .inst_ready_o;
  wire [9:0] hs = {`TH .narrow_out_req.aw_valid, `TH .narrow_out_req.w_valid,
                   `TH .narrow_out_req.ar_valid, `TH .narrow_out_resp.b_valid,
                   `TH .narrow_out_resp.r_valid,
                   `TH .wide_out_req.aw_valid, `TH .wide_out_req.w_valid,
                   `TH .wide_out_req.ar_valid, `TH .wide_out_resp.b_valid,
                   `TH .wide_out_resp.r_valid};

  int fd[N];
  bit          have[N];
  logic [31:0] ppc[N], pins[N];
  longint      pt[N];
  int unsigned nret[N], ncyc = 0, nerr = 0;

  initial for (int i = 0; i < N; i++)
    fd[i] = $fopen($sformatf("logs/gls_hart_%05x.txt", i), "w");

  task automatic xerr(string what, int i, logic [63:0] v);
    nerr++;
    if (nerr <= 20) $error("GLS_X %s hart %0d value %h", what, i, v);
  endtask

  always @(posedge clk) begin
    #(SMP_PS * 1ps);
    if (rst_n !== 1'b1) begin
      ncyc = 0;
      for (int i = 0; i < N; i++) have[i] = 0;
    end else if (ncyc < 5) ncyc++;   // X check / trace armed after 5 cycles
    else begin
      if ($isunknown(hs)) xerr("axi handshake", -1, hs);
      if (`TH .narrow_out_req.aw_valid && $isunknown(`TH .narrow_out_req.aw.addr)) xerr("narrow aw.addr", -1, 0);
      if (`TH .narrow_out_req.ar_valid && $isunknown(`TH .narrow_out_req.ar.addr)) xerr("narrow ar.addr", -1, 0);
      if (`TH .wide_out_req.aw_valid && $isunknown(`TH .wide_out_req.aw.addr)) xerr("wide aw.addr", -1, 0);
      if (`TH .wide_out_req.ar_valid && $isunknown(`TH .wide_out_req.ar.addr)) xerr("wide ar.addr", -1, 0);
      for (int i = 0; i < N; i++) begin
        automatic logic [31:0] pc = {addr[i*48+2 +: 30], 2'b00};
        automatic logic [31:0] ins = data[i*32 +: 32];
        if ($isunknown({valid[i], ready[i]})) xerr("fetch handshake", i, {valid[i], ready[i]});
        if (valid[i] === 1'b1 && $isunknown(pc)) xerr("fetch pc", i, pc);
        if (valid[i] === 1'b1 && ready[i] === 1'b1 && $isunknown(ins)) xerr("fetch insn", i, ins);
        if (have[i] && pc !== ppc[i]) begin
          $fdisplay(fd[i], "%0d %h %h", pt[i], ppc[i], pins[i]);
          nret[i]++;
        end
        have[i] = valid[i] === 1'b1 && ready[i] === 1'b1;
        ppc[i] = pc; pins[i] = ins;
        pt[i] = longint'($realtime / 1ps) + TCK_PS - SMP_PS;
      end
      if (++ncyc % 2000 == 0) $display("GLS_HB cycle %0d hart0 retired %0d", ncyc, nret[0]);
    end
  end

  final begin
    $display("GLS_TRACE retired %p x_errors %0d", nret, nerr);
    for (int i = 0; i < N; i++) $fclose(fd[i]);
  end
endmodule
