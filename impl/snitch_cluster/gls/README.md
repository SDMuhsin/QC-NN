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
$G sdf; $G compile sdf            # optional: DC tt SDF (usask), then start/wait/summary with sdf
$G report                         # -> results.txt
```

| file | role |
|---|---|
| `gls.sh` | all steps; host `GLS_HOST` (tau5), work area `/tmp/ckp908/qcnn_snitchgls` |
| `mk_compile.py` | bender compile script of `sim/` -> GLS script: RTL wrapper -> its package only, + cells, ARM models, netlist |
| `gls_trace.sv` | second top: per-hart retire trace (time, pc, insn) from the I-cache fetch ports, X check |
| `gls_summary.py` | verdict, kernel cycles, retire-by-retire comparison with the RTL run |
| `write_sdf.tcl`, `sdf_idealclk.py` | DC `write_sdf` at tt, ideal-clock view of it |

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

## SDF run (tt): not finished

What exists: `gls.sh sdf` writes the tt SDF in DC (`write_sdf.tcl`). STA: setup slack +1.37 ns
at 4 ns, worst hold -0.10 ns on a TCDM macro pin, pre-CTS. The ideal-clock view zeroes the 6541
ICGs, which are the whole clock network. `compile sdf` adds the ARM timing models and a copy of
`tb_bin` with `TCK = GLS_TCK_PS`. The run uses `+no_notifier`, so the unfixed pre-CTS hold
violations are reported but do not X the registers.

Status: the run does not track RTL. The first instruction retires in the same cycle as RTL.
After that, the I-cache stops issuing the next wide-AXI AR in the same cycle as the R beat, so
bootrom fetches take 34 instead of 24 cycles, and a later fetch returns stale data.
A 10 ns clock gives the same result, so it is not a setup problem. The cause is still open.
Candidates are the ARM timing models or the use of `+no_notifier`. zd already shows the netlist
matches RTL cycle for cycle.
