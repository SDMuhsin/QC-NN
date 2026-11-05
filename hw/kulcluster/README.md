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
