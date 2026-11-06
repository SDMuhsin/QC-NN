# hw/kulcluster — KUL cluster for chimera's `TARGET_KULCLUSTER` slot

chimera (tag CONVOLVE-TO) instantiates `KULCluster_snax_KUL_cluster_wrapper` from the private
`gitlab.tue.nl:es/convolve-private/kulcluster`. This package rebuilds it from the public SNAX
sources: **KULeuven-MICAS/snax_cluster @ 3575d72** (6 Dec 2024), config `snax_KUL_cluster.hjson`
(2 Snitch cores: core 0 drives the Chisel **GeMMX** accelerator (8x8x8 int8 array + SIMD rescale)
via its streamer/CSR manager, core 1 drives the Chisel xDMA; 128 KiB TCDM in 32 banks).

## Config tweaks (`cfg/snax_KUL_cluster_chimera.hjson` vs upstream)
| field | upstream | here | why |
|---|---|---|---|
| `user_width` | 3 | 2 | chimera narrow AXI user = `AxiUserWidth` 2 |
| `dma_user_width` | 1 | 2 | chimera wide AXI user = 2 (else 751 vs 754 bit wide req) |
| `observable_pin_width` | 8 | 0 | wrapper has no `obs_o` |
| `enable_debug` | false | true | wrapper connects `debug_req_i` |
| `sram_cfg_expose` | true | false | wrapper has no `sram_cfgs_i` |

## Packaging
`gen.sh` clones snax_cluster, runs `make rtl-gen` (Chisel 6 via sbt, JDK 11), then pickles the
cluster with **morty** (`--top snax_KUL_cluster_wrapper -p KULCluster_`) and
`scripts/prefix_fixup.py` (renames the units morty leaves unprefixed, drops Chisel's duplicate
`ram_8x64`/`DataPathExtension_*` copies). Every module/package/interface is `KULCluster_*`, macros
are expanded, so the package has no dependencies and cannot clash with chimera's own
`snitch_cluster` (same package name) / axi / common_cells. Three pickles (tool `ifdef`s resolved
at pickling): `generated/kulcluster_sim.sv` (Questa/VCS), `_vlt.sv` (`VERILATOR`,`SYNTHESIS` as
the upstream snax Verilator flow), `_syn.sv` (`SYNTHESIS`); `Bender.yml` selects by target.
`generated/` is git-ignored (3 x 6 MB), regenerate with `gen.sh`.

Hooked into chimera by `third_party/.bender.yml` (override `kulcluster -> hw/kulcluster`) and the
matching `Path:` line in `third_party/chimera/Bender.lock` (that file was already locally modified
for the other stubs). The old stub `tools/convolve_private_stubs/kulcluster` was removed.

## Reproduce
```bash
hw/kulcluster/setup_tools.sh          # JDK 11, sbt, morty 0.9.0, LLVM 17, venv -> tools/
hw/kulcluster/gen.sh                  # ~3 min -> generated/*.sv
hw/kulcluster/run_standalone.sh       # SNAX Verilator TB: gemmx-matmul / conv / xdma-memset
hw/kulcluster/lint/lint_chimera.sh    # Verilator lint of chimera_top_wrapper + KUL (~1.5 min)
hw/kulcluster/sim/prep_chimera_ws.sh  # private chimera copy + chs-hw-init in build/kulcluster/
hw/kulcluster/sw/chimera_gemmx/build.sh
hw/kulcluster/sim/chimera_vsim.sh     # Questa 2022.1 on tau1: compile + run (~11 min), exit 0 = PASS
hw/kulcluster/flist.sh synth          # file list for synthesis (see notes inside)
```

## Chimera test (`sw/chimera_gemmx`)
CVA6 (JTAG-preloaded into the memory island) releases cluster 3 from reset/clock gate and offloads
`kul_entry` via chimera's `offloadToCluster`; core 0 (hart 7) copies A/B/C into its TCDM
(0x4060_0000), programs streamer + GeMMX with snax's `snax-gemmx-lib.c` and the golden data of
snax's `snax-gemmx-matmul` (M=1,K=18,N=2: 8x144 x 144x16 int8, SIMD rescale to int8), runs it and
compares D8 with the golden result; host returns 0 iff the kernel ran and had 0 mismatches.

### Cycle measurement (`results/gemmx_cycles.txt`)
* `kul_gemm.c` stores phase timings (mcycle) and the GeMMX/streamer hardware performance
  counters (CSRs `GEMMX_PERFORMANCE_COUNTER`, `STREAMER_PERFORMANCE_COUNTER`) in `kul_result[]`.
  `kul_result[2]` ("window", start CSR writes .. busy polls done) is a *software* window: core 0
  fetches every instruction from the memory island (~25 cycles each), so it is dominated by the
  ~13 instructions of start/poll code, not by the accelerator. Use the counters / probes instead.
* `sim/gemmx_probe.tcl` (sourced by `run_chimera.tcl`) logs the BlockGemm / SIMD / streamer busy
  edges and the MAC-array A/B handshakes; `chimera_vsim.sh run` then calls
  `scripts/gemmx_cycles.py` (output in `build/kulcluster/vsim_run/gemmx_cycles.txt`).
* Standalone twin: `sw/standalone_gemmx_perf/gemmx_perf.c`, built and run by
  `run_standalone.sh` as `snax-gemmx-matmul-perf` (prints a `GEMMX_PERF` line); run it before
  `chimera_vsim.sh` to get both columns in one table.

## Gate-level simulation (`gls/`, results in `results/gls.txt`)
The DC netlist of `impl/kulcluster` (`kul_p3.5`) replaces the cluster RTL in the full chimera Questa
run: same TB, host ELF and self-check as `sim/chimera_vsim.sh`. `gls/mk_compile.py` swaps the
`kulcluster_sim.sv` block of the bender compile script for the TSMC cell models, the ARM RF macro
models and the netlist. The top module name and port widths are the same, so chimera binds it unchanged.
```bash
# prereqs: sim/chimera_vsim.sh compile, sw/chimera_gemmx/build.sh, DC netlist + macro views on the host
hw/kulcluster/gls/gls.sh compile zd; hw/kulcluster/gls/gls.sh start zd   # zero delay, ~10 min
hw/kulcluster/gls/gls.sh wait zd      # repeat until GLS_DONE
hw/kulcluster/gls/gls.sh summary zd   # -> results/gls_zd.log (PASS/FAIL, cycles vs RTL)
hw/kulcluster/gls/gls.sh sdf          # DC write_sdf at tt (+ flow/tsmc65/sim/sdf_idealclk.py), then the same 4 steps with `sdf`
```
* `zd`: `+nospecify +notimingchecks`, macro models in ARM unit-delay mode (`ARM_UD_MODEL`).
  `sdf`: DC `write_sdf` at tt, full macro timing models, timing checks on, cluster clock 3.5 ns
  (pre-CTS tt fmax ~433 MHz). `flow/tsmc65/sim/sdf_idealclk.py --clock-celltype CKLNQD` makes the SDF consistent with the STA:
  * ICG CP->Q delays and the `rst_ni` buffer tree are zeroed, because they are ideal networks in
    synthesis.
  * The input ports get the SDC input delay of 0.7 ns. chimera's RTL changes them 0 ps after the
    edge, and with the cells' tt hold windows Questa would then sample the next cycle's value
    without reporting it.

  See `impl/snitch_cluster/gls/README.md`, "SDF run (tt)".
* Probes (`gls_probe.tcl`): the busy nets and perf-counter flops that survive synthesis (GeMM
  core / SIMD / streamer), in the same GEMMX_PROBE format as the RTL run.
* X handling: no X suppression. All resettable state uses its RTL reset (async-reset flops).
  Non-reset flops and the macros start at X, as in RTL. `gls_xcheck.sv` (bound into chimera's
  `chimera_cluster_kulcluster`) flags any X on the cluster's AXI handshakes, on valid AW/AR
  addresses and on valid R data. Busy nets are logged in binary, so an X there fails the summary.
* Status: `zd` PASS and cycle-exact with RTL (GeMM busy 40, SIMD 51, streamer 76 counters).
  `sdf` (tt, 3.5 ns, on tau5 with `KUL_VSIM_HOST=tau5`) PASS: 0 timing-check errors, 0 X, and
  cycle-exact with zd at the same 3.5 ns clock (GeMM 40, SIMD 51, streamer 71). The streamer is
  5 cycles shorter than at chimera's default 2 ns, where RTL ran. That comes from the clock, not
  from the delays (`results/gls.txt`). Debug knobs: `GLS_STOP=<time>` (stop early) and
  `KUL_GLS_SIMARGS=+GLS_HSLOG=<n>` (log the first n AXI handshake changes).
* Netlist warnings that do not matter: vopt-2685/2718 are unconnected outputs. vopt-2958 (8805 undriven
  implicit nets) are DC's dangling nets on input-port bits with no load inside the submodule.
  `gls.sh undriven` checks this statically: 7657 resolved, 0 loaded, 1148 concatenations not resolved.

## Workarounds / limitations
* chimera's snitch bootrom never sets `sp`; `kul_entry` sets a stack at the TCDM top.
* Infineon HyperRAM model no longer downloadable -> stub `sim/models/s27ks0641_stub.v`
  (+`POST_SYNTH` define to skip its SDF annotation). Test does not use HyperRAM.
* Verilator lint only: cheshire's `axi_rt_unit_top.sv` rewritten with typedefs (V5.044 limitation),
  hyperbus behavioural `configurable_delay` added. No functional change.
* chimera needs `chs-hw-init` (CLINT 18 harts, PLIC 36) in its bender checkouts; this is done in
  the private copy `build/kulcluster/chimera_ws` only (pass `CHIM=build/kulcluster/chimera_ws` to
  `flist.sh` for an initialised tree).
* fesvr for the SNAX TB is built `--without-boost`; `dtc` is a shim.
