# impl/snitch_cluster/gls: gate-level simulation of the Snitch cluster netlist

The DC netlist `fp_p4.0` (`snitch_cluster_wrapper`, see `../README.md`) replaces the RTL
`snitch_cluster_wrapper` in the `sim/` Questa testbench. The TB, kernel ELFs and self-checking
verifiers are the same as in `sim/run_kernel.sh <kernel> vsim`. Results: `results.txt`.

```sh
G=impl/snitch_cluster/gls/gls.sh
$G setup                          # netlist + macro models usask -> tau5, sim/build_hw.sh vsim on tau5
sim/run_kernel.sh gemm_fp64 vsim  # (once per kernel) RTL run, provides the ELF
$G compile rtl; $G compile zd     # ~2 min each
$G start gemm_fp64 rtl; $G wait gemm_fp64 rtl; $G summary gemm_fp64 rtl   # same for conv2d, then zd
$G sdf; $G compile sdf            # DC tt SDF (usask) + sdf_idealclk.py (tau5, ~4 min), then start/wait/summary with sdf
$G report                         # -> results.txt
```

| file | role |
|---|---|
| `gls.sh` | all steps; host `GLS_HOST` (tau5), work area `/tmp/ckp908/qcnn_snitchgls` |
| `mk_compile.py` | bender compile script of `sim/` -> GLS script: RTL wrapper -> its package only, + cells, ARM models, netlist |
| `gls_trace.sv` | second top: per-hart retire trace (time, pc, insn) from the I-cache fetch ports, X check |
| `gls_summary.py` | verdict, kernel cycles, retire-by-retire comparison with the RTL run |
| `write_sdf.tcl`, `sdf_idealclk.py` | DC `write_sdf` at tt; STA-consistent view of it (ideal clock + reset, SDC input delay) |

## Method

* **Cycle counts.** The cores are ungrouped in the netlist, so the upstream tracer is gone.
  `gls_trace.sv` watches the I-cache fetch ports of the 9 cores, which survive in the netlist.
  An instruction retires in the last cycle it is fetched (valid & ready) before pc changes.
  Kernel cycles use the `gen_trace.py` rule: hart-0 regions between `csrr mcycle` reads.
  Mode `rtl` runs the same monitor on the RTL. There its stream equals the upstream tracer's
  core instructions on all 9 harts, and it gives 6518 / 18587 cycles. The GLS stream is then
  compared with the RTL stream for every retire: time, pc and instruction.
* **zd.** `+nospecify +notimingchecks`, ARM models in unit-delay mode (`ARM_UD_MODEL`).
  Each ARM model is compiled in its own `vlog`, because the models `` `define ARM_UD_SEQ `` in
  their own timescale. In one compilation unit, the SP model's `#10` (ps) became 10 ns in the RF model.
  The I-cache data RF then never updated Q, and harts fetched zeros.
* **X handling.** No X suppression. Reset flops take their RTL reset values. Non-reset flops and
  macro contents start at X, as in RTL. The TCDM gets data by DMA before use, and the I-cache
  init writes every line. `gls_trace.sv` raises `$error` (GLS_X) on X in fetch handshakes, valid
  pcs, accepted instructions, cluster AXI handshakes and valid AW/AR addresses. Any such error
  fails the run.
* **Warnings that do not matter.** vopt-2685/2718 are unconnected cell outputs (carry-outs).
  vopt-2958 (11479) are DC's dangling nets on unused port bits (e.g. pc[1:0], addr[47:32]).

## SDF run (tt)

`gls.sh sdf` writes the tt SDF in DC (`write_sdf.tcl`, wire-load, pre-CTS; STA setup slack
+1.37 ns at 4 ns, worst hold -0.10 ns on a TCDM macro pin). `sdf_idealclk.py` turns it into the view
that the STA signed off. Then `compile sdf` adds the ARM timing models and a copy of `tb_bin` with
`TCK = GLS_TCK_PS` (default 4000). The run uses `+no_notifier`, so a timing violation is reported
(and fails the summary through "Questa errors") but does not X the register.

`sdf_idealclk.py` applies the three SDC assumptions that the raw SDF does not model:

1. **Ideal clock.** The IOPATHs of the 6541 ICGs (the whole clock network, `clock_cells.txt`) are
   zeroed. STA uses ideal clocks, and CTS balances this insertion delay later.
2. **Ideal reset.** `rst_ni` is `set_ideal_network` and a false path in the SDC. The 5908
   buffers/inverters DC hung on it (found from the SDF INTERCONNECTs, through input pin `I`) are
   zeroed. Their wire-load delays (up to ~1.3 ns) put the reset release on a clock edge for some
   flops. Without this, the run gets 84 `$hold(CP, CDN)` removal errors at 12 ns.
3. **Input delay.** Every INTERCONNECT from a top-level input port except `clk_i` gets the SDC
   `set_input_delay` (0.8 ns, used as both min and max). `gls.sh sdf` reads it from the SDC.

**Root cause of the earlier divergence (item 3).** The RTL testbench changes the cluster inputs in
the NBA region of the clock edge, so 0 ps after the edge. Some port-to-register paths are only about
10 ps long. Example: wide `ar_ready` -> `i_axi_dma_xbar/gen_mst_port_mux_1__i_axi_mux/
gen_mux_i_ar_spill_reg/.../gen_spill_reg_b_full_q_reg`, through one NR2D0. The tt SDF gives that DFCNQD1
`SETUP (negedge D) -0.016` and `HOLD (negedge D) 0.037`. Questa honours negative `$setuphold` limits
by building internal delayed copies of D and CP (vsim-3819 "Scheduled event on delay net"). The
flop then samples D about 37 ps after the edge. So it takes the value that the TB drove for the NEXT
cycle, and the timing check, which now runs on the delayed signals, is met. The result is a hold
violation that is never reported. `ar_ready` was seen one cycle early, the mux spill register
dropped `ar_valid` without a real handshake, and the I-cache refill lost an AR. That is the "34
instead of 24 cycles" bootrom fetch and the stale line seen before. The clock period does not matter
(4 ns and 10 ns failed the same way), because the problem is hold at the boundary. The STA was
consistent: with the SDC's 0.8 ns input delay these paths meet hold. Zero-delay GLS has no hold
windows, so it did not see the problem. The other hypotheses were checked and ruled out:
* clock-net INTERCONNECTs are all 0 in this SDF;
* the ARM models annotate cleanly, and their Q path is (posedge CLK => Q);
* there are no ICG problems beyond the zeroing in item 1;
* `+no_notifier` was not the cause, because no check fired.

Results: gemm_fp64 and conv2d at tt, 4 ns, give a PASS self-check, 0 Questa errors (no timing
violation) and 0 X. Kernel cycles equal RTL, and every retire (pc, insn, cycle) is identical to RTL
on all 9 harts (`results.txt`).
* The comparison counts cycles from each hart's first retire. With 0.8 ns, the reset is released
  one edge later than in the RTL TB, where the reset and the clock edge race at 30 ns.
* tb_bin polls fesvr every 200 ns, so at 4 ns the run reaches `$finish` at most 50 cycles after
  the exit. RTL can run up to 200 cycles past it. The last few RTL retires (wfi loop) are after this run's end.
  `gls_summary.py` leaves them out and reports their count.
