# sim/ — NN workloads on chimera's Snitch cluster (RTL)

The CONVOLVE accelerators in chimera are private, so the NN accelerator under test
is chimera's open Snitch cluster (`hw/chimera_cluster.sv`). Workloads run on the
upstream standalone testbench of the `snitch_cluster` dependency
(`target/snitch_cluster`, rev c12ce9b pinned by chimera), and the output is checked
against a golden model with the upstream verification framework.

## Quick start

```bash
sim/setup.sh                    # fetch toolchain + spike-dasm, stage build/sim/ws/chimera_fp
sim/build_hw.sh vsim            # Questa 2022.1_2 on tau1   (or: vlt = local Verilator 5.044)
sim/run_kernel.sh gemm_fp32 vsim
sim/run_all.sh vsim             # all kernels -> sim/results/summary_vsim_chimera_fp.txt
```

`<sim>` is `vlt` (local; the first build takes tens of minutes) or `vsim` (remote Questa, ~20 s build).

## Layout

| path | role |
|---|---|
| `env.sh` | tool paths (LLVM, bender, venv, Verilator, remote host) |
| `setup.sh` | fetches prebuilt tools into `tools/`, stages a workspace copy |
| `build_hw.sh <sim> [cfg]` | builds the testbench (`bin/snitch_cluster.{vlt,vsim}`) |
| `run_kernel.sh <kernel> <sim> [cfg]` | build SW, simulate, self-check, traces, summary |
| `run_all.sh <sim> [cfg]` | every kernel + summary table |
| `cfg/chimera_fp.hjson` | cluster config matching chimera (see below) |
| `kernels/<k>.conf/.hjson` | kernel: upstream app, data-generator params, verifier, timed regions |
| `verify/` | conv2d datagen wrapper and verifier (see below) |
| `mk/overlay.mk` | make overlay, adapts the upstream flow to Verilator 5 |
| `lib/` | shell helpers, shims, `summarize.py` |
| `results/` | per-run summaries (tracked) |

Everything generated (workspaces, ELFs, traces) is under the git-ignored `build/sim/`.
Upstream sources are copied to `build/sim/ws/<cfg>` and built there; nothing in
`third_party/` is modified.

## Toolchain and tools

* pulp-platform/llvm-project **0.12.0** prebuilt (`riscv32-pulp-llvm-ubuntu2004`), the
  version pinned in snitch_cluster's `iis-setup.sh` → `tools/riscv-llvm`.
* snitch `spike-dasm` 0.1.0 (pinned in its Dockerfile) → `tools/spike-dasm`.
* Python: `tools/venv` (+ `setuptools<81`, which reggen needs for `pkg_resources`).
  On tau a separate venv lives in `$REMOTE_WORK/venv`.
* `dtc` shim: fesvr's configure only checks that `dtc` exists.

## Cluster configuration (`cfg/chimera_fp.hjson`)

Copied from the `snitch_cluster` instance in `chimera_cluster.sv`/`chimera_pkg.sv`:
9 cores (8 compute + DMA core), 128 KiB TCDM in 16 banks, 64-bit narrow / 512-bit
wide (DMA) bus, 1 KiB I-cache (2 sets × 16 × 256 b), DMA 3 in flight / FIFO depth 3,
4 outstanding AXI transactions, core/offload register cuts, VM off.

**One deviation:** chimera leaves `RVF/RVD/Xssr/Xfrep` at the snitch_cluster default
(0), so as instantiated its cluster has **no FPU, SSRs or FREP** (integer-only).
All upstream DNN/BLAS kernels and the snRuntime (`-mabi=ilp32d`) need these, so
the compute cores keep the upstream default template (rv32imafd + SSR + FREP +
SIMD FP). Everything else matches chimera.

## Kernels and checking

| kernel | source | data | check |
|---|---|---|---|
| `gemm_fp32` | `sw/blas/gemm`, upstream default params (16³, `gemm_fp32_opt`) | upstream datagen | upstream `verify.py` (rtol 1e-6) |
| `gemm_fp64` | same, 32³ `gemm_fp64_opt` | upstream datagen | upstream `verify.py` (rtol 1e-6) |
| `gemm_fp16` | same, 32³ `gemm_fp16_opt` | upstream datagen | upstream `verify.py` (rtol 1e-2) |
| `conv2d` | `sw/dnn/conv2d`, upstream default layer (FP64) | `verify/conv2d_datagen.py` | `verify/conv2d_verify.py` (rtol 1e-6) |

The verifier talks to the running simulation over IPC, reads the output buffer back
and compares it with the golden model (numpy/PyTorch). `results.csv` per run keeps
every expected/actual pair.

conv2d is disabled in upstream CI ("fails with wrong results"): its `verify.py`
uses an API that no longer exists, its datagen fills the output buffer with the
golden result (so an unwritten output would pass), and the golden model uses CHW
while the kernel uses HWC. Our datagen wrapper zero-fills the output; our verifier
reads ifmap/weights/ofmap in the kernel's HWC layout and checks against
`torch.nn.functional.conv2d`.

**Cycle counts.** The upstream trace tools (`spike-dasm` + `util/trace/gen_trace.py`)
split each hart's trace at every `mcycle` read. *kernel* = hart-0 regions the
kernel brackets with `snrt_mcycle()` (`REGIONS` in the `.conf`); *total* = last
retired instruction on any hart (includes boot, DMA in/out, barriers). Clock 1 GHz
in the TB, so cycles = ns.

## Remote (Questa) details

`build_hw.sh vsim` makes the bender compile script locally (paths rewritten to the
remote copy), rsyncs the workspace to `$REMOTE_HOST:$REMOTE_WORK/ws/<cfg>` and runs
the upstream `bin/snitch_cluster.vsim` recipe there. A stand-in bender
(`lib/bender-replay.sh`) replays that script. The work area is `/tmp/ckp908/qcnn_work_sim`
on tau1 because the NFS home is over quota (`~/qcnn/work_sim` gave "Disk quota
exceeded"). Change `REMOTE_HOST`/`REMOTE_WORK` in the environment to move it.

## Verilator 5 notes (`mk/overlay.mk`)

Upstream expects Verilator 4.110. For 5.044 we add `-DASSERTS_OFF` (V5 rejects SVA
`until_with` in `snitch_lsu.sv`), `--no-timing` and a few lint waivers, and we link
`verilated_threads.o`. Cycle counts agree with Questa to within 0.5 %: the gemm
compute regions are cycle-identical, and the totals differ by a constant
boot/reset offset plus small DMA timing differences.

## Not covered

* Chimera SoC-level offload test (`sw/tests/testClusterOffload.c`): needs the whole
  cheshire/chimera SoC build, including bootroms built with a riscv64 GCC toolchain,
  and the stubbed private clusters. Not attempted.
* Bit-exact integer-only chimera cluster: the snRuntime and the kernels need an FPU.
