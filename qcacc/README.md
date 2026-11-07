# qcacc/ — QC-GeMMX accelerator for the `qc/` model s2 (milestone M1: host side)

Spec: [`ARCH.md`](ARCH.md).  M1 = weight codec, bit-exact array model, compiler (two modes), schedule model,
C runtime (native x86 + chimera ELF).  Reuses `nn/` by import (layouts, streamer CSRs, allocator, emitter,
schedule model, `nn/sw` runtime unchanged).  No RTL yet.

| file | contents |
|---|---|
| `model/codec.py` | int8 W -> one 64-bit code per 8x8 tile (16 blocks x 4 b, ARCH.md), decoder; `row_signs` (pairs stored as `-M`), conv0 padded channels as don't-care; raises if not encodable |
| `model/array.py` | bit-exact numpy QC-GeMMX array (butterfly + select, int32 acc) + select activity counters |
| `model/test_model.py` | random QC tiles and all s2 layers: codec round trip, array == dense GEMM, rejection tests |
| `compile/lower.py` | `QCProgram(q, mode)`: one GeMMX call per 8-output-channel group, modes `gemmx` / `qc` |
| `compile/sim.py` | QC call on the TCDM image (hook `gemm=` of `nn.compile.schedule_sim.run_image`) |
| `compile/main.py` | driver: schedule model vs `IntResNet8`, select stats, C emit, calls / bytes / cycle model |
| `sw/native_qc.c` | `nn/sw/native/native.c` with the array replaced by a C model of the QC datapath |
| `sw/native.sh`, `sw/build.sh` | native x86 run / chimera ELF of `build/MODE/gen` through `nn/sw` |

## Commands (outputs in `qcacc/build/`, git-ignored)
```bash
python3 -m qcacc.model.test_model                         # codec + array model tests (exit 1 on failure)
python3 -m qcacc.compile.main --mode gemmx --acc          # control: 1000 images bit-exact, 10k int8 accuracy, -> build/gemmx/gen
python3 -m qcacc.compile.main --mode qc                   # QC-GeMMX: 1000 images bit-exact, select stats  -> build/qc/gen
qcacc/sw/native.sh gemmx [-DNN_FULL_CHECK]                # nn/sw on x86, GeMMX C model: exit 0 = bit-exact (8 images)
qcacc/sw/native.sh qc    [-DNN_FULL_CHECK]                # nn/sw on x86, QC-GeMMX C model
qcacc/sw/build.sh dense|gemmx|qc                          # chimera ELF (tools/llvm17), prints weight blob bytes
```
Inputs: `/tmp/$USER/qc/final/int8/s2.pt` (`qc/final.sh int8 s2`, or `qc/fetch.sh`), `nn/build/qparams.pt`
(dense baseline, for the cycle comparison), CIFAR-10 in `nn/data` (`nn/fetch.sh`).

## Mapping
* Per conv one blob in the memory island, per 8-channel group g: `[B tiles][bias tile 256 B][nn_conv_t]`
  (64 B aligned parts).  Each group call is one runtime step (`convX_gG`) whose output is plane g of the
  conv's C8HW8 tensor, so `nn/sw/nn_cluster.c` runs both modes unchanged (prefetch one conv ahead, per-group
  checksums).  A / C / D8 streamers: as `nn/compile` (implicit im2col, D8 64 B aligned), with N = 1.
* `gemmx`: B = int8 ternary weights, dense GeMMX layout.  `qc`: B = `[ci8][kh][kw]` code words (uint64 LE).
* Sign flips (qc): `row_signs` keeps row 2j and flips row 2j+1 iff the pair needs it (s2: conv5 6, conv8 7
  rows); flipped rows store M with negated bias (C) and negated SIMD multiplier (`|m| < 2^31`, exact).

## QC B streamer CSRs (assumed; the RTL milestone implements them)
Same `nn_conv_t` / `set_gemmx_streamer_csr` register map; the B reader has **1 spatial channel of 64 b**:

| CSR | value | meaning |
|---|---|---|
| `Bslstride0` | 1 | unused (no spatial unrolling inside the word) |
| `Bslstride1` | 0 | unused (1 channel) |
| `Btlbound0`, `Btlstride0` | K, 8 | one 8 B code word per fire (K = kh·kw·Cin/8) |
| `Btlbound1`, `Btlstride1` | N (= 1), 8·K | output-channel group |
| `Btlbound2`, `Btlstride2` | M, 0 | weights re-read for every 8-pixel tile |
| `delta_local_b` | blob + group offset | 64 B aligned (8 B would suffice) |
| `subtraction_b` | 0 | ignored by the QC array |

## Results (s2, `/tmp/root/qc/final/int8/s2.pt`)
| | dense baseline (`nn/`) | s2 `gemmx` (control) | s2 `qc` |
|---|---|---|---|
| int8 accuracy, 10k (`IntResNet8`) | 87.30 % | **80.41 %** | 80.41 % |
| schedule model vs `IntResNet8`, 1000 images (46 step outputs + logits each) | bit-exact (`nn/`) | **0 mismatches** | **0 mismatches** |
| native C run, 8 images (+ `NN_FULL_CHECK` image 0) | exit 0 | exit 0 | exit 0 (C QC array) |
| GeMMX calls / image (array fires) | 9 (25 856) | 42 (25 856) | 42 (25 856) |
| B tile bytes | 77 440 | 77 440 | **9 680** (11 008 64 B padded) |
| conv blobs in the ELF (B + bias tiles + `nn_conv_t`) | 91 072 | 101 632 | 35 200 |
| cycle model / image (GeMMX steps) | 370 458 (33 400); RTL 401.7 k | 374 418 (37 360) | 374 418 (37 360) |

* Cycle model: same 8x8x8 fire rate in both modes (K fires + 1 per tile); +33 calls x 120 cycles of CSR
  overhead vs the baseline.  The residual adds on the cores (~316 k) still dominate; the weight DMA was already
  hidden, so 8x less B traffic shows up in energy, not cycles.  ELFs embed 8 images (dense: 2).
* QC select activity (1000 images): 6.62 M tile muxes / image, 80.5 % with a nonzero code, 48.4 % select a
  nonzero value; per conv in the `--mode qc` output (conv0 42 %: Cin 3 padded to 8).
* `nn/` hooks (backward compatible, defaults = old behaviour): `schedule_sim.run_image(..., gemm=None)`,
  `nn/sw/native/run.sh` env `NN_NATIVE_C`, `NN_NATIVE_BUILD`.  `python3 -m nn.compile.main --images 2`
  output and `nn/build/gen` are byte-identical to before; `nn/sw/native/run.sh` exits 0.

## Open risks for the RTL milestone
1. B streamer with one 64-bit channel (the CSR values above) and its handshake with an array that consumes
   64 b per fire; the per-fire B bank access pattern changes (1 bank instead of 8).
2. Negative SIMD multipliers (flipped rows): `RescalePE` takes `multiplier_i` as SInt(32), so `-m` is exact
   by the Chisel source, but never exercised in RTL so far (s2: conv5, conv8).
3. 42 calls instead of 9: CSR programming per call from TCDM (~120 cycles assumed) is not measured yet.
4. conv0 padded input channels: decoded weights may be nonzero there (don't-care); correct only because the
   A padding holds the zero point (`subtraction_a`), as in `nn/`.

# M2a — RTL (QC-GeMMX cluster) and first verification

| file | contents |
|---|---|
| `hw/chisel/qcgemm/QcGemmArray.scala` | QC array: `QcRowButterfly` (per row: x = a - subtraction_a, s_p, d_p), `QcColumnDecoder` (per column, 64-bit code word), `QcTile` (4-term select-sum; accumulator / add-C / control = dense `Tile`), `QcMesh`, `QcGemmArray` (A / C / D bit layout = dense) |
| `hw/chisel/qcgemm/QcBlockGemm.scala` | dense `BlockGemm` verbatim except the array and B width (64 b); `QcBlockGemmEmit` (unit TB) |
| `hw/chisel/qcgemm/QcBlockGemmRescaleSIMD.scala` | dense `BlockGemmRescaleSIMD` verbatim with `QcBlockGemm`, emitted under the dense module name |
| `hw/sv/snax_streamer_gemmX_shell_wrapper.sv` | upstream shell wrapper, `DataWidthB = 64` |
| `hw/patches/snax_cluster_qc.patch` | snaxgen runs `QcBlockGemmRescaleSIMDGen`; streamer: the transposer only on 512-b readers (upstream `require`s every reader to be 512 b when `has_transpose`), the B reader keeps its unused CSR slot -> **CSR map identical** to the dense cluster |
| `hw/cfg/snax_KUL_cluster_qc.hjson` | `hw/kulcluster` config with the B reader 1 ch x 64 b; B moves to the narrow TCDM ports (wide ports = 512-b superbank groups): A 0-7, B 8, D8 9-16, C/D32 17-48, xDMA 49-64 |
| `hw/gen.sh` | `hw/kulcluster/gen.sh` on a separate checkout `build/qcacc/snax_cluster` + overlay -> `build/qcacc/generated/kulcluster_{sim,vlt,syn}.sv` (same `KULCluster_` prefix / top: drop-in) |
| `hw/tb/` | Verilator TB of `QcBlockGemm` vs `model/array.py` (`vectors.py`, `tb_qc_blockgemm.cpp`, `run.sh`) |
| `hw/sim/run_rtl_qc.sh`, `hw/sim/summary.py` | `nn/sim/run_rtl.sh` with the QC pickles (remote work dir `/tmp/ckp908/qcacc_kul`), the qc-mode compiler and the QC tree's headers; results in `build/qcacc/rtl/<tag>/` |

Hooks in the base (defaults unchanged): `hw/kulcluster/sim/chimera_vsim.sh` env `KUL_WS`, `KUL_GEN`;
`nn/sim/prep.sh` env `NN_COMPILE`; `nn/sim/run_rtl.sh` env `NN_RTL_OUT`; `nn/sim/run_nn.tcl` probes
`KULCluster_QcBlockGemm` when there is no `KULCluster_BlockGemm`.

```bash
qcacc/hw/gen.sh                                  # ~2.5 min
qcacc/hw/tb/run.sh [stall%]                      # unit TB, exit 0 = bit-exact
qcacc/hw/sim/run_rtl_qc.sh -S conv1_g1 -H usask  # conv0 + conv1 in chimera (Questa), byte-exact check
qcacc/hw/sim/run_rtl_qc.sh -H usask -n 1         # whole network, image 0
```

## M2a results (2026-11-07)
* `gen.sh`: 2 min 18 s.  Unit TB (`hw/tb/run.sh 30`): 200 random cases + all 42 QC calls of s2 image 0
  (29 574 fires, A/B/C/D random stalls on every other case): **0 bad D words**, bit-exact; full-rate cases busy
  16 027 cycles vs M·N·(K+1) = 15 785.
* chimera + QC cluster, Questa 2022.1 on usask (tau-02), cluster clock 2 ns:
  * `-S conv1_g1` (NN_FULL_CHECK): conv0 + conv1 byte-exact.  conv1 (2 calls, 4608 fires): GeMMX busy 5372,
    streamer 5374 (dense GeMMX conv1: 6162 busy, 1 call).
  * whole network, image 0: **logits bit-exact**, every per-group checksum OK (incl. the sign-flipped rows of
    conv5 / conv8, i.e. negative SIMD multipliers), 475 715 cycles (dense RTL 401.7 k); GeMMX busy 31 913.
    The extra cycles are per-call overhead: ~2.2 k cycles per group call outside the GeMMX busy window
    (cycle model assumed 120), x 42 calls.
