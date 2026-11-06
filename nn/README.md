# nn/ — MLPerf Tiny ResNet-8 (CIFAR-10) on the KUL GeMMX cluster

Host-side flow (phase 1): float model, int8 quantization that maps one-to-one onto the GeMMX hardware arithmetic,
a compiler that lowers the network to the cluster, a C runtime for chimera, and two independent bit-exact checks.
No RTL simulation is done here.

| dir | contents |
|---|---|
| `model/` | `resnet8.py`: ResNet-8 in PyTorch, Keras `pretrainedResnet.h5` loaded with h5py, BN folded, Keras `same` padding (stride 2 pads right/bottom only). `data.py`: CIFAR-10 loader (raw 0..255 pixels, as the model was trained) |
| `quant/` | `hw.py`: bit-exact GeMMX / RescaleSIMD / core arithmetic. `quantize.py`: PTQ, and `IntResNet8`, the integer-only PyTorch reference |
| `compile/` | `lower.py`: layouts, GeMMX CSR values, TCDM liveness allocator. `schedule_sim.py`: TCDM-image model of the schedule and cycle model. `emit.py`: C tables and data. `main.py`: driver |
| `sw/` | `nn_cluster.c` (cluster runtime, both cores), `nn_host.c` (CVA6 offload), `nn_entry.S`, `build.sh` (chimera ELF), `native/` (host x86 run of the same C on a C GeMMX model) |

```bash
nn/fetch.sh                                   # pretrainedResnet.h5 + CIFAR-10 -> nn/data/ (git-ignored)
python3 -m nn.model.resnet8                   # float accuracy
python3 -m nn.quant.quantize                  # -> nn/build/qparams.pt, float + int8 accuracy (10k images)
python3 -m nn.compile.main --images 2         # schedule model vs reference, -> nn/build/gen/, plan + cycles
nn/sw/native/run.sh [-DNN_FULL_CHECK]         # C runtime on x86 with a C GeMMX model: exit 0 = bit-exact
nn/sw/build.sh [-DNN_FULL_CHECK] [-DNN_NO_DMA]  # -> nn/build/sw/resnet8.memisl.elf (tools/llvm17, as hw/kulcluster/sw)
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
| TCDM peak | 74.5 KiB of 124 KiB arena (4 KiB at the top for the mailbox and stacks) |
| ELF in the memory island | 117 KiB with 2 images (weights + bias tiles 87 KiB, 9 KiB per image), 240 KiB with `NN_FULL_CHECK` |
| estimated cycles / image | **~370 k**: GeMMX steps ~33 k, residual adds on the cores ~316 k, pool+FC ~20 k |

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

* Every tensor is stored as `[C/8][H+2][W+2][8]` with a 1-pixel zero-point border. D8 writes straight into the
  interior of the next layer's padded buffer, so there is no repacking. 3x3/s1 windows start at padded (0,0).
  Keras stride-2 windows (3x3/s2 and 1x1/s2) start at (1,1).
* B is `[Cout/8][Cin/8][Kh][Kw][8co][8ci]`. C is one 256 B int32 tile per Cout/8 group (broadcast reader, M
  stride 0). Each tile holds all 8 rows, so it is also correct if the broadcast extension were bypassed.
* Data movement: core 1 runs the Snitch iDMA (`dmsrc/dmdst/dmcpyi`) from a TCDM job queue. Core 0 wakes it
  through its CLINT msip. Weights and bias tiles are prefetched one conv ahead. Buffers are placed by a
  liveness-based first-fit allocator, so stage-3 weights (37 KiB) reuse the dead stage-1 activations. The DMA
  copies are hidden behind the previous step. `-DNN_NO_DMA` falls back to core 0 word copies.
* Residual adds are split by rows between core 0 and core 1. Pool+FC runs on core 0. After every step core 0
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

## Open risks for the RTL phase

1. **Streamer strides that are not multiples of 64 B.** D8 and A use 8-byte-granular strides such as
   `8*(W+2)` = 272/144/80 with interleaved addressing (`addr_remap_index = 0`). Upstream asserts `%64` only for
   its banked layout. Upstream ran the conv mode with remap 2 and the matmul with remap 0. If the writer needs
   64 B alignment, pad W+2 up to a multiple of 8 pixels in `lower.Tensor`.
2. **C broadcast and `channel_en_C = 0xFF`.** These copy the upstream values. The full 8x8 tiles make the result
   independent of the broadcast semantics.
3. **Core 1 start-up and iDMA.** The wake-up path (msip of hart 8, then bootrom, then `nn_entry`) and the wide
   AXI path from the cluster iDMA to the memory island (`WIDE_MEM_CLUSTER_3_BYPASS` default) have not been
   exercised in chimera. `-DNN_NO_DMA` isolates DMA problems.
4. **Simulation length.** ~370 k cycles per image plus the untimed checksums (~100 k), on top of the boot. `NN_FULL_CHECK`
   adds slow narrow reads from the memory island. Start with `--images 1`.
5. **Hart id.** `KUL_HART0 = 7` (cluster 3 = 1 + 2 + 2 + 2) is hard-coded in `build.sh`.
