# QC-NN: chimera CONVOLVE-TO on TSMC 65 nm

A reproduction of [pulp-platform/chimera](https://github.com/pulp-platform/chimera), tag `CONVOLVE-TO`
(commit 1b89d12), on TSMC 65 nm (CMC kit `tcbn65gplus`, 200a libraries) on the tau servers.  It covers RTL
simulation of NN kernels, Synopsys DC synthesis, PrimeTime STA at ss / tt / ff, gate-level simulation (zero-delay and
SDF), and OpenROAD place and route (not finished) for the two compute clusters that can be built from public sources.

## Scope and deviations

* **Private accelerators.**  chimera's five CONVOLVE accelerator clusters are private TU/e GitLab repos.  Four of them
  (`tuedcim`, `tuemega`, `tuddcim`, `ethcluster`) are empty stubs (`tools/convolve_private_stubs/`, wired up in
  `third_party/.bender.yml`).
* **KULCLUSTER** is replaced by its public equivalent, KU Leuven
  [SNAX `snax_cluster` @ 3575d72](https://github.com/KULeuven-MICAS/snax_cluster) with the GeMMX accelerator (8x8x8
  int8 MAC array + SIMD rescale), packaged to fit chimera's `TARGET_KULCLUSTER` slot (`hw/kulcluster/`).
* **Snitch cluster FPU.**  chimera's own Snitch cluster is integer-only (no FPU / SSR / FREP), but the upstream DNN and
  BLAS kernels need an FPU.  The kernels therefore run on chimera's cluster parameters with the upstream FP compute
  cores (`sim/cfg/chimera_fp.hjson`, variant `fp`).  The chimera-exact integer config (variant `chimera`) was also
  synthesised.
* **Node.**  The chimera paper's silicon is GF 22 nm FDX, not TSMC.  Every paper number below is normalised before it
  is compared.

## Repository layout

| dir | contents |
|---|---|
| `flow/tsmc65/` | design-agnostic DC / PrimeTime / VCS flow, SRAM compiler wrapper, site templates ([README](flow/tsmc65/README.md)) |
| `flow/tsmc65/pnr/` | OpenROAD P&R flow, captable RC, DEF-to-SPEF, GDS merge ([README](flow/tsmc65/pnr/README.md)) |
| `hw/tech/tsmc65/` | technology overlay: `tc_sram` on ARM macros, `tc_clk` on kit clock cells, the macro list and its test |
| `hw/kulcluster/` | SNAX KUL cluster package for chimera, standalone and in-chimera simulation, gate-level simulation ([README](hw/kulcluster/README.md)) |
| `impl/snitch_cluster/` | Snitch cluster synthesis / STA, `gls/` gate-level simulation, `pnr/` ([README](impl/snitch_cluster/README.md)) |
| `impl/kulcluster/` | KUL cluster synthesis / STA and `pnr/` ([README](impl/kulcluster/README.md)) |
| `sim/` | NN kernels on the Snitch cluster RTL (Questa / Verilator), with golden-model checks ([README](sim/README.md)) |
| `nn/` | MLPerf Tiny ResNet-8 on the KUL GeMMX cluster: model, int8 quantization, compiler, C runtime, host-side bit-exact checks ([README](nn/README.md)) |
| `qc/` | ResNet-8 with quasi-cyclic (QC) conv weights: training, QC verifier, int8 export through `nn/quant`, storage/addition stats ([README](qc/README.md), [results](qc/RESULTS.md)) |
| `third_party/` | chimera submodule, bender overrides, `Bender.lock` patch |
| `tools/` | git-ignored local tools; only `convolve_private_stubs/` is tracked |

Kit and macro views (LEF, liberty, .db, GDS, vendor Verilog models) are never tracked.  They stay on the servers,
and the paths to them are set in git-ignored site files (`flow/tsmc65/site/*.example.*` are the templates).

## Results

All synthesis numbers are DC with the kit's area-selected wire-load model (`WireAreaLowkCon`, enclosed), followed by
PrimeTime pre-CTS with ideal clocks.  fmax = 1 / (period - WNS).  kGE uses NAND2 = 1.44 um2.  Earlier runs used the
library default `ZeroWireload` (Snitch `fp_p4.0`: 250 MHz ss, 2700 kGE; KUL `kul_p3.5`: 284 MHz ss, 1476 kGE).  Those
runs are optimistic and superseded, and are kept only for reference in the sub-READMEs.

### Snitch cluster (`fp` variant: 8 FP compute cores + DMA core, 128 KiB TCDM)

| stage | result |
|---|---|
| RTL kernels (Questa; `sim/results/`) | all PASS: gemm_fp64 32^3 **6518** kernel cycles, gemm_fp32 16^3 1462, gemm_fp16 32^3 2832, conv2d (FP64) 18587.  Verilator gives the same gemm cycles; conv2d is 18522 (within 0.5 %). |
| GLS zero-delay | PASS, 6518 cycles = RTL, retire stream (time, pc, insn) identical on 9/9 harts.  This is gemm_fp64 on `fp_p5.0_wlm`; conv2d zd also passes, on the superseded `fp_p4.0`. |
| GLS SDF (tt, 4 ns) | gemm_fp64 and conv2d PASS: 0 timing-check errors, 0 X, cycles = RTL.  Run on the `fp_p4.0` netlist only. |
| synthesis `fp_p5.0_wlm` | 5.93 mm2 total = 4.01 mm2 logic (**2785 kGE**) + 1.92 mm2 SRAM; fmax ss / tt / ff **200** / 309 / 442 MHz; 68 mW tt (vectorless) |
| synthesis, `chimera` variant (integer-only) | `snc_p2.0`, zero WLM only: 2.98 mm2, 742 kGE, 412 / 618 / 849 MHz |
| P&R (OpenROAD) | **incomplete**: OOM in detailed route.  Run on `fp_p4.0`; the last checkpoint is after CTS, with global route at ss -8.41 ns. |

### KUL cluster (SNAX, GeMMX; 2 Snitch cores, 128 KiB TCDM in 32 banks)

| stage | result |
|---|---|
| RTL in chimera (Questa) | PASS, 0 mismatches vs golden D8 (int8 8x144 x 144x16 GeMM + SIMD rescale).  GeMM core busy **40** cycles for the ideal 36 (36 back-to-back MAC fires); SIMD 51; streamer 76 (`hw/kulcluster/results/gemmx_cycles.txt`). |
| standalone SNAX TB (Verilator) | PASS; GeMMX counter 55, streamer 56 |
| GLS zero-delay (2 ns) | PASS, all six cycle counters = RTL, 0 X on the AXI handshakes |
| GLS SDF (tt, 3.5 ns) | PASS, 0 timing-check errors, 0 X, cycle-exact with zd at 3.5 ns.  The streamer is 5 cycles shorter than RTL at 2 ns, which comes from the clock (`results/gls.txt`). |
| synthesis `kul_w4.2` | 4.04 mm2 total = 2.17 mm2 logic (**1509 kGE**) + 1.87 mm2 RF macros; GeMMX 1.01 mm2 (702 kGE); fmax ss / tt / ff **229** / 354 / 503 MHz; 231 mW tt (vectorless) |
| synthesis `kul_w4.2p` (same flow, current RTL with the icache PMA fix) | 4.05 mm2, 1513 kGE, fmax 233 / 357 / 506 MHz (+0.2 % area, +1 % fmax: noise) |
| ResNet-8 RTL in chimera (`nn/`) | 30 / 30 images bit-exact vs PyTorch int8, 401.7 k cycles / image ([nn/results/rtl.md](nn/results/rtl.md)) |
| ResNet-8 GLS, conv1 on `kul_w4.2p` | zd 2 ns and SDF tt 2.8 / 5 ns: output bit-exact, cycles and GeMMX counters = RTL at the same clock, 0 timing-check errors ([nn/results/gls_power.md](nn/results/gls_power.md)) |
| conv1 SAIF power (PT PX, tt, pre-CTS) | 357 MHz: **332 mW** (GeMMX 59 %), 5.7 uJ / layer, **2.4 pJ/MAC** cluster (1.4 GeMMX) = 0.82 TOPS/W; 200 MHz: 194 mW; ~101 uJ / image extrapolated (adds on the cores dominate) |
| P&R (OpenROAD) | **incomplete**: stopped in global route.  Post-CTS: ss WNS -3.67 ns (~127 MHz), skew 1.52 ns (`impl/kulcluster/pnr/results/kul_pnr4.txt`) |

The GeMM-test GLS runs used the superseded zero-WLM netlist `kul_p3.5`; the ResNet-8 GLS uses `kul_w4.2p`.  P&R used `kul_w4.2`.

## Paper sanity check

There is no published 65 nm number for any of these blocks.  Utilisation, cycles and kGE are compared directly.
Frequency is scaled by an FO4 rule of thumb (22 nm FDX to 65 nm: 1.5-2x slower; 16 nm FinFET to 65 nm: 2.5-3.5x).

| quantity | ours (TSMC 65, ss unless noted) | paper | node | normalised expectation | verdict |
|---|---|---|---|---|---|
| GeMMX MAC utilisation | 90 % (36 ideal / 40 busy) | 82-99 % (OpenGeMM [2]), 92 % large tiles (SNAX [3]) | 16 nm | node-independent | **in range** (small job: add-C / drain cycles weigh more) |
| GeMMX fmax | 229 MHz ss, 354 MHz tt | 800 MHz (SNAX syn. [3], Voltra silicon [4]) | 16 nm | ss 200-330, tt 250-450 MHz | **in range** |
| GeMMX conv energy | 0.82 TOPS/W cluster, 1.39 GeMMX only (conv1, SAIF, tt 1.0 V, pre-CTS) | 4.68 TOPS/W (OpenGeMM [2], 0.675 V); 1.6 TOPS/W (Voltra [4] silicon, 0.6 V) | 16 nm | 0.53-0.71 ([2]); 0.14-0.19 ([4]) TOPS/W | **above**, x1.2-1.6 vs [2], x4-6 vs [4] (no clock tree / ideal clock, WLM; see `nn/results/gls_power.md`) |
| GeMMX area | 702 kGE (GeMM + SIMD 561, streamer 135) | not reported; OpenGeMM core ~0.063 mm2 [2] | 16 nm | ~300-750 kGE (first principles: 200-450 core + 100-300 streamers / SIMD) | **plausible**, upper half |
| KUL cluster area | 4.04 mm2 (2.17 logic + 1.87 RF) | KUL cluster not reported in [1]; SNAX cluster 0.45 mm2 [3] | 16 nm | < 7.4 mm2 ((65/16)^2 upper bound; the configs differ) | **consistent**, weak check |
| Snitch FP64 GEMM | 6518 cycles for 32^3 on 8 cores = 63 % FPU util. | 8-core 32^2 DGEMM 85-87 % (Snitch TC [5]); 89 % at 48^2 (Occamy [6]) | 22 / 12 nm | node-independent | **plausible, lower**: 2 tiles of M = 16, and SSR setup / barriers / DMA waits are inside the timed regions |
| Snitch cluster logic | 2785 kGE | 3.3 MGE incl. 8 KiB I$ + 32-bank TCDM (Snitch TC [5]) | 22 nm | 1.6-2.6 MGE for this config | **above** (+7 %): this config adds SIMD FP8 / FP16 / sdotp FPUs (FP subsystem ~200 kGE per core) |
| Snitch cluster fmax | **200 MHz ss**, 309 tt | 755 MHz SSG 0.72 V, 1.06 GHz TT (Snitch TC [5]) | 22 nm | ss 350-500, tt 530-700 MHz | **below** (see next paragraph) |

**Why Snitch fmax is low.**  The limit is not the FPU pipeline: the fpnew latencies equal upstream, and FPU datapaths
are only ~16 % of the 53.8k near-critical endpoints.  It is the single-cycle core <-> TCDM request / grant round trip
(FREP sequencer -> FP LSU -> TCDM crossbar -> SSR / scoreboard) and the fetch -> decode -> LSU loop of the integer
core.  Both are 70-85 cells deep at 65 nm ss.  The DC topographical run gives the same 198 MHz, so the wire-load model
is not the cause.  One knob differs from upstream: `register_fpu_req: false` (chimera default) is `true` upstream.  It
would cut only the first path class, and the design was not changed (`impl/snitch_cluster/README.md`).

Sources: [1] Leone et al., CHIMERA, arXiv:2606.02358 (GF22 silicon; reports only the TAC cluster); [2] Yi et al.,
OpenGeMM, ASP-DAC 2025, arXiv:2411.09543; [3] Antonio, Dumoulin et al., SNAX, ISLPED 2025, arXiv:2508.14582;
[4] Yi et al., Voltra, ISCAS 2026, arXiv:2602.11357; [5] Zaruba et al., Snitch, IEEE TC 2021, arXiv:2002.10143;
[6] Scheffler et al., Occamy, JSSC 2025, arXiv:2501.07330.

## Reproduce

Server runs need `flow/tsmc65/site/` filled in from the templates and `QC_BUILD=/tmp/$USER/qcnn/build`.  The commands
below are the entry points.  Prerequisites, hosts and options are in the linked READMEs.

| stage | command | details |
|---|---|---|
| checkout | `git submodule update --init; (cd third_party/chimera && ../../tools/bender/bin/bender update tuedcim tuemega tuddcim kulcluster ethcluster)` | `third_party/.bender.yml` overrides use relative paths; `bender update` of the five overridden packages rewrites their `Path:` lines in `Bender.lock` for your checkout (`third_party/patches/chimera-Bender.lock.patch` shows the change for `/workspace/qc-nn`) |
| flow smoke test | `flow/tsmc65/smoke/run.sh` | [flow/tsmc65](flow/tsmc65/README.md) |
| SRAM macros | `flow/tsmc65/sram/mc_gen.sh gen hw/tech/tsmc65/macros.txt` | [flow/tsmc65](flow/tsmc65/README.md) |
| Snitch RTL kernels | `sim/setup.sh; sim/build_hw.sh vsim; sim/run_all.sh vsim` | [sim](sim/README.md) |
| Snitch synthesis + STA | `impl/snitch_cluster/run.sh all 5.0` | [impl/snitch_cluster](impl/snitch_cluster/README.md) |
| Snitch GLS | `impl/snitch_cluster/gls/gls.sh setup / compile / start / wait / summary / sdf` | [gls](impl/snitch_cluster/gls/README.md) |
| Snitch P&R | `impl/snitch_cluster/pnr/run.sh pnr; impl/snitch_cluster/pnr/run.sh pt` | config `impl/snitch_cluster/pnr/snitch_fp.cfg` |
| KUL generate | `hw/kulcluster/setup_tools.sh; hw/kulcluster/gen.sh` | [hw/kulcluster](hw/kulcluster/README.md) |
| KUL in chimera (RTL) | `hw/kulcluster/sim/prep_chimera_ws.sh; hw/kulcluster/sw/chimera_gemmx/build.sh; hw/kulcluster/sim/chimera_vsim.sh` | [hw/kulcluster](hw/kulcluster/README.md) |
| KUL synthesis + STA | `impl/kulcluster/run.sh macros; impl/kulcluster/run.sh all 4.2` | [impl/kulcluster](impl/kulcluster/README.md) |
| KUL GLS | `hw/kulcluster/gls/gls.sh compile\|start\|wait\|summary zd\|sdf` | [hw/kulcluster](hw/kulcluster/README.md) |
| ResNet-8 RTL / GLS + power | `nn/sim/run_rtl.sh`; `nn/gls/run_gls.sh`, `nn/gls/power.sh` | [nn](nn/README.md), [gls_power](nn/results/gls_power.md) |
| KUL P&R | `impl/kulcluster/pnr/run.sh pnr kul_pnr4` | `impl/kulcluster/pnr/results/kul_pnr4.txt` |
| OpenROAD install | `flow/tsmc65/pnr/install_openroad.sh` | [pnr](flow/tsmc65/pnr/README.md) |

## Known limitations and open items

* **OpenROAD P&R is incomplete for both clusters.**  Snitch: detailed route was OOM-killed (31 GB RSS on a 30 GB host),
  on the superseded `fp_p4.0` netlist.  KUL: global route was still running after 2.9 h and was stopped.  After CTS,
  skew is 1.52 ns and ss WNS -3.67 ns.  No routed netlist, SPEF, post-route STA or GDS exists for either.
* **Commercial P&R is unavailable.**  The Cadence licence server refuses user `ckp908`; a CMC admin has to add it to
  the INCLUDE list.  ICC2 / Fusion Compiler are not installed.
* **The ARM memory macros have no GDS** (front end and LEF abstracts only), so a merged GDS would keep them as
  abstracts.
* **The kit has no extraction deck** (no QRC / OpenRCX rules).  Parasitics come from the captables (one R / C per
  layer, no coupling), so post-route timing is indicative only.
* **M1 two-via rule.**  The router reads a LEF copy without the M1 `MINIMUMCUT` rule.  Single-cut VIA1 on wide pins
  would fail a sign-off DRC.
* **Kerberos tickets expire after 10 h.**  Renew with `~/bin/tau-reauth` or `kinit -R`, otherwise long remote runs lose
  access to the NFS home.
* **The NFS home is over quota**, so builds, tools and work trees use host-local `/tmp/$USER/...`.  These exist on
  one host only.
* **The SoC-level Snitch offload test** (`testClusterOffload.c`) needs the full cheshire / chimera build with a riscv64
  GCC toolchain for the bootroms.  It was not run.
* **GeMMX copy-in in chimera** uses a core-0 load / store loop from the memory island (722k cycles) instead of the
  cluster DMA.  Only the accelerator counters are meaningful as performance numbers.
* Power is PrimeTime vectorless (no switching activity) for the cluster-level numbers, so those are
  order-of-magnitude estimates.  The ResNet-8 conv1 power is SAIF-based (gate-level activity), but pre-CTS:
  there is no clock tree and the clock is ideal.
