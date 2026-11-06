# nn/ — MLPerf Tiny ResNet-8 (CIFAR-10) on the KUL GeMMX cluster

Phase 1 (host): float model, int8 quantization that maps one-to-one onto the GeMMX hardware arithmetic, a
compiler that lowers the network to the cluster, a C runtime for chimera, and two independent bit-exact checks.
Phase 2 (RTL): the whole network runs in the full chimera SoC on Questa, bit-exact against the PyTorch int8
reference; results in [`results/rtl.md`](results/rtl.md).

| dir | contents |
|---|---|
| `model/` | `resnet8.py`: ResNet-8 in PyTorch, Keras `pretrainedResnet.h5` loaded with h5py, BN folded, Keras `same` padding (stride 2 pads right/bottom only). `data.py`: CIFAR-10 loader (raw 0..255 pixels, as the model was trained) |
| `quant/` | `hw.py`: bit-exact GeMMX / RescaleSIMD / core arithmetic. `quantize.py`: PTQ, and `IntResNet8`, the integer-only PyTorch reference |
| `compile/` | `lower.py`: layouts, GeMMX CSR values, TCDM liveness allocator. `schedule_sim.py`: TCDM-image model of the schedule and cycle model. `emit.py`: C tables and data. `main.py`: driver |
| `sw/` | `nn_cluster.c` (cluster runtime, both cores), `nn_host.c` (CVA6 offload), `nn_entry.S`, `build.sh` (chimera ELF), `native/` (host x86 run of the same C on a C GeMMX model) |
| `sim/` | `run_rtl.sh` (RTL run on a tau host), `run_nn.tcl` (Questa script), `memisl.py` (memory-island backdoor image + result decode), `summary.py`, `tcdm_check.py` (debug: TCDM dump vs reference) |
| `results/` | `rtl.md` (phase 2 results), `rtl_logs/` (per-run summaries) |

```bash
nn/fetch.sh                                   # pretrainedResnet.h5 + CIFAR-10 -> nn/data/ (git-ignored)
python3 -m nn.model.resnet8                   # float accuracy
python3 -m nn.quant.quantize                  # -> nn/build/qparams.pt, float + int8 accuracy (10k images)
python3 -m nn.compile.main --images 2         # schedule model vs reference, -> nn/build/gen/, plan + cycles
nn/sw/native/run.sh [-DNN_FULL_CHECK]         # C runtime on x86 with a C GeMMX model: exit 0 = bit-exact
nn/sw/build.sh [-DNN_FULL_CHECK] [-DNN_NO_DMA]  # -> nn/build/sw/resnet8.memisl.elf (tools/llvm17, as hw/kulcluster/sw)
nn/sim/run_rtl.sh -H tau1 -n 10 -f 0          # RTL: test images 0..9 in chimera on Questa (see results/rtl.md)
```
Python: `nn/requirements.txt` (torch, numpy, h5py).

## Results

| | |
|---|---|
| float (BN folded), CIFAR-10 test, 10k | **87.19 %** |
| int8 reference (`IntResNet8`), 10k, lane weight scales (default) | **87.30 %** |
| int8, per-tensor weight scales (`--wgran tensor`) | 86.89 % |
| int8, max calibration (`--pct 100`) | 87.17 % |
| schedule model vs integer reference | bit-exact, every step output and the logits, 1000 test images |
| native C run (`sw/native/run.sh`) vs reference | bit-exact checksums and logits (8 images; `NN_FULL_CHECK` byte compare of image 0) |
| GeMMX calls / image | **9** (one per conv), 25 856 array fires, 94.4 % of the fired MACs are useful (only conv0 pads Cin 3 to 8) |
| TCDM peak | 79.8 KiB of 124 KiB arena (4 KiB at the top for the mailbox and stacks) |
| ELF in the memory island | weights + bias tiles + conv parameters + add tables 89 KiB, 10.7 KiB per image; `NN_FULL_CHECK` adds 120 KiB (1 image only) |
| estimated cycles / image | ~370 k (phase 1 model); **measured in RTL: see [`results/rtl.md`](results/rtl.md)** |

Calibration: 2000 training images, 99.99th percentile of each activation tensor.

## Quantization = hardware arithmetic

The arithmetic is taken from the Chisel source of the pinned `snax_cluster` (`hw/chisel_acc/.../gemm/GemmTileArray.scala`,
`simd/RescalePE.scala`). `quant/hw.py` documents it:

* GeMM: `acc = C + sum (a - subtraction_a)(b - subtraction_b)`, int32.
* SIMD lane (lane = output channel % 8): `var1 = int32(((acc - izp) * m) >> (s-1))`, then `(var1 >> 1) + ozp`,
  then a clamp to [min, max], with `double_round = 0`. This is `floor(acc * m / 2^s)`. `double_round = 1` rounds
  negative values asymmetrically and is not used. Instead the round-to-nearest offset `2^(s-1)/m` is added to the
  bias in C.
* Activations are per-tensor int8. ReLU outputs use zp = -128, so the full 8 bits cover x >= 0 and ReLU is the
  lower clamp. Conv outputs that feed a residual add are symmetric. The input is pixel - 128 (scale 1), which is
  lossless. The input zero point goes into `subtraction_a`, and padding is filled with the zero point.
* Weights are symmetric int8 with one scale per SIMD lane (channels c, c+8, ...), so every lane has its own
  multiplier and shift and each conv is still one call.
* Residual add on the cores: `clamp(((a-za)*ma + (b-zb)*mb + 2^15) >> 16) + zo`. The C folds the constants.
  Global average pool is an exact channel sum, followed by an int8 FC to int32 logits (argmax is unaffected by
  the common scale).

## Mapping (why the native conv mode)

Each conv uses the streamer's implicit-im2col conv mode, the same one as `snax-gemmx-conv` upstream. The A reader
walks Kw/Kh/Cin8 over a C8HW8 tensor, so im2col is never materialised and no core work is needed. Every layer of
ResNet-8 has an output width that is a multiple of 8 (32/16/8), which this mode requires. Explicit im2col would
cost core cycles and TCDM for a 9x copy.

* Every tensor is stored as `[C/8][H+2][W+8][8]` (+ a 64 B tail) with a zero-point border. The interior starts
  at column 8, so every D8 tile and row is 64 B aligned: the D8 writer ignores address bits [5:0] (found in RTL,
  phase 2). Column 7 is the left border, column 0 of the next row the right border. D8 writes straight into the
  interior of the next layer's padded buffer, so there is no repacking. 3x3/s1 windows start at padded (0, 7).
  Keras stride-2 windows (3x3/s2 and 1x1/s2) start at (1, 8). The A reader handles 8 B granular addresses.
* B is `[Cout/8][Cin/8][Kh][Kw][8co][8ci]`. C is one 256 B int32 tile per Cout/8 group (broadcast reader, M
  stride 0). Each tile holds all 8 rows, so it is also correct if the broadcast extension were bypassed. The
  call's `nn_conv_t` (streamer + GeMMX CSR values) follows the bias tiles in the same blob, so core 0 programs
  the CSRs from TCDM rather than with ~80 slow narrow loads from the memory island.
* Data movement: core 1 runs the Snitch iDMA (`dmsrc/dmdst/dmcpyi`) from a TCDM job queue. Core 0 wakes it
  through its CLINT msip. Weights and bias tiles are prefetched one conv ahead. Buffers are placed by a
  liveness-based first-fit allocator, so stage-3 weights (37 KiB) reuse the dead stage-1 activations. The DMA
  copies are hidden behind the previous step. `-DNN_NO_DMA` falls back to core 0 word copies.
* Residual adds are split by rows between core 0 and core 1; the clamp is a DMA'd lookup table indexed by the
  shifted sum (no branches, ~10 instructions per element). Pool+FC runs on core 0. After every step core 0
  checksums the output (Fletcher-32 over the interior; not timed) and compares it with the reference, and it
  compares the logits exactly. `nn_result` (memory island) holds per-step mcycle counts, the GeMMX/streamer
  counters, the logits and the first mismatching step.

## Cycle estimate (`compile/schedule_sim.py`, cluster clock, per image)

* GeMMX steps: M·N·(K+1) per call (K fires + 1 add-C cycle per output tile; the measured upstream job is 40 busy
  for 36 fires), plus ~120 for the CSRs, start and drain, plus the border fill. Total ~33 k.
* Residual adds: ~19 instructions per element in `add_rows` (from objdump), modelled as 22 cycles, split over 2
  cores. 28 672 elements give ~316 k. This dominates. The fix would be to run the adds on GeMMX as a 1x1 GEMM over
  channel-concatenated inputs with diagonal weights, which cuts the total to ~60 k cycles. The spec puts the
  adds on the cores, so this was not done.
* TCDM bank conflicts and instruction-fetch misses (code runs from the memory island) are not modelled. Phase 2
  should read the real numbers from `nn_result.cycles` and the GeMMX perf counters.

## RTL phase: what the open risks turned out to be

1. **Non-64 B strides.** The A reader is fine with 8 B granular addresses; the **D8 writer drops address bits
   [5:0]**, which shifted every output tile. Fixed in the layout (interior at column 8, row pitch W+8).
2. **C broadcast, `channel_en_C`.** No issue.
3. **Core 1 wake-up and iDMA.** Both work as written (msip -> boot ROM trap -> `nn_entry`; iDMA over the wide
   port to the memory island).
4. **Simulation length.** Solved by a memory-island backdoor (8 B JTAG stub, `mem load` of the 32 banks):
   ~2-3 min of Questa per image after a ~1 min boot.
5. **Hart id 7.** Correct for chimera cluster 3.

Two integration problems outside `nn/` showed up: the KUL cluster's icache PMA cached only DRAM (fixed in
`hw/kulcluster/cfg`), and CVA6's boot ROM stack (just below 0x4801_0000) clobbers a backdoor-loaded image
(`run_nn.tcl` reloads at the host's first instruction).  Details in `results/rtl.md`.
