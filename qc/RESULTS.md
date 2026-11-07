# QC ResNet-8 on CIFAR-10: results

Every conv of the MLPerf Tiny ResNet-8 is trained so that its weight matrix is quasi-cyclic (QC). The matrix is tiled
into b x b blocks, and each block is zero or the sum of at most two distinct cyclically shifted identities. A
per-output-channel scale and bias follow each conv (folded BatchNorm). All numbers are on the full 10k CIFAR-10 test
set and were measured once, on the final checkpoints. Every selection decision used a fixed 45k/5k train/val split.
Per-layer tables are in [`results/`](results/), and the overview is in [`results/summary.md`](results/summary.md).

## Headline

| model | b | weights | density | weight storage vs dense int8 | additions vs dense MACs | float test % | int8 test % | int8 vs 87.30 |
|---|--:|---|--:|--:|--:|--:|--:|--:|
| baseline (Keras pretrained, `nn/`) | – | int8 | 1 | 613 760 bits | 12.50 M MACs | 87.19 | 87.30 | – |
| dense, our training recipe | – | float | 1 | – | – | 87.56 | – | – |
| **s2** | 2 | QC on [x; −x] (−1/0/1) | 0.608 | 0.188 | 0.606 | **80.70** | **80.41** | −6.89 |
| s4 | 4 | QC on [x; −x] (−1/0/1) | 0.384 | 0.063 | 0.379 | 72.03 | 72.00 | −15.30 |
| s8 | 8 | QC on [x; −x] (−1/0/1) | 0.218 | 0.020 | 0.206 | 65.56 | 65.41 | −21.89 |
| **u2** | 2 | strict QC (0/1) | 0.248 | 0.125 | 0.266 | **66.93** | **66.67** | −20.63 |
| u4 | 4 | strict QC (0/1) | 0.178 | 0.047 | 0.186 | 61.72 | 61.83 | −25.47 |
| u8 | 8 | strict QC (0/1) | 0.120 | 0.016 | 0.112 | 55.43 | 55.28 | −32.02 |
| s4w2 (2x channels, not ResNet-8) | 4 | QC on [x; −x] | 0.384 | – | – | 82.72 | – | – |
| s8w2 (2x channels, not ResNet-8) | 8 | QC on [x; −x] | 0.212 | – | – | 77.51 | – | – |

**Bottom line: QC conv weights cost ResNet-8 a lot of accuracy.** The best QC model (s2) loses 6.9 points in int8.
Holding to the strict 0/1 definition costs at least 20.6 points (u2). At b=8, the size that matches the GeMMX 8x8
tile, the loss is 22 points (s8) or 32 points (u8).

All 8 checkpoints pass `qc.verify` (float, folded). All 6 width-1 int8 models pass `qc.verify_int8`, which checks
that the int8 weight tensors themselves are QC. Int8 accuracy stays within 0.3 points of float for every model.

Definitions (`qc/stats.py`):
- **Storage** counts weight bits only. One QC block takes 2 slots x (valid bit + log2 b shift bits + a sign bit for
  s\*). Dense is 8 bits per weight. Per-channel scales and biases are left out on both sides.
- **Additions** = Hout·Wout·(nnz − cout) per layer: each output accumulates its nonzeros, and terms that land on zero
  padding are not skipped. Subtractions count as additions. Each model also needs 86 016 per-channel scale multiplies
  per image (the baseline's requant has the same). The FC layer (dense int8 in every model) is excluded throughout.

## Decisions and their justification

* **Matrix view (hwc).** A conv's matrix is the GEMM matrix `[cout, kh·kw·cin]` with columns ordered (kh, kw, cin).
  This is the im2col order of the existing compiler and of the GeMMX B layout `[Cout/8][Cin/8][Kh][Kw][8co][8ci]`, so
  every b x b block sits inside one kernel tap, and at b=8 it is exactly one GeMMX weight tile. The alternative
  (cin, kh, kw), where blocks mix taps, was never better (ablation below). conv0's 3 input channels are zero-padded
  to 8, as the hardware already does.
* **Strict 0/1 vs signed.** Under the strict definition every output channel is a scaled sum of a subset of its
  inputs, so one channel cannot compute a difference such as an edge filter. That costs 8–17 points at every b. The
  s\* models therefore use the one extension we state:

  - **Mechanism:** each conv sees its input stacked with its negation, `[x; −x]`. Its weight matrix `[P N]` is then a
    strict 0/1 QC matrix with the same b and at most two shifts per block. In fact each b x b block of the signed
    matrix `W = P − N` has at most two signed shifts in total.
  - **Cost:** at inference this is an adder that subtracts instead of adds. There are no extra operations, and
    storage needs one sign bit per shift slot.
  - **Prior work:** the concatenated-negation idea is CReLU (Shang et al., ICML 2016).
* **Other things beyond the bare definition.** A per-output-channel bias, which is the GeMMX C input. The dense
  int8 FC layer, which is not a convolution. A shortcut-conv BatchNorm (conv5/conv8 had none in the Keras model),
  which folds into the allowed scale and bias.

  In the int8 export, rows whose scale is negative store −M rather than M, because the existing requant multiplier
  is positive-only. `qc.verify_int8` counts these rows and accepts sign(s)·M.
* **Block size.** The full sweep b ∈ {1, 2, 4, 8} is in the table below; the final models cover b = 2, 4 and 8.
  b=1 means unconstrained binary or ternary weights, so it isn't QC and is only a reference.

## Training method (final recipes)

* **Signed (`--method qat`).** One real latent coefficient per (block, shift), which makes it a block-circulant
  parametrisation, as in CirCNN (Ding et al., MICRO 2017) and PermDNN (Deng et al., MICRO 2018).
  - **Forward pass:** hard −1/0/1 values in every forward pass. A coefficient is zero when its magnitude is below
    0.5 x the block row's mean (a TWN-style threshold).
  - **Shift selection:** the top-2 shifts per block are re-chosen from the latent magnitudes every step for the first
    half of training, then frozen.
  - **Gradients and optimiser:** straight-through estimator on the latents, which are trained with Adam (lr 1e-3,
    cosine, no weight decay), in the style of Bi-Real/ReActNet. BN and FC use SGD with nesterov momentum and
    weight decay 5e-5.
  - **BN:** statistics are recalibrated on training data before each validation.
* **Unsigned (`--method staged`).**
  - **Stages:** real block-circulant (20% of epochs), then magnitude pruning to 2 shifts per block (20%), then a ramp
    to hard 0/1 with the straight-through estimator (60%).
  - **Distillation:** from our dense model trained on the 45k split only (α 0.5, T 4). The Keras model was not used
    as teacher because it was trained on the val images.
* Both recipes: 200 epochs, random crop + horizontal flip, input = raw pixels as in `nn/`, about 6 s/epoch on one A40.

## What was tried, what failed, and why

Validation accuracy (5k split). 100 epochs unless noted. The seed-to-seed spread is about ±0.7.

| step | finding |
|---|---|
| 1. Supermask scores (top-2 per block, STE, Adam), b=8, 200 ep | **Failed.** u 51.1, s 64.5. Scores started at std 0.01 and Adam moved them by about 10% per step, so the shifts chosen per block never settled. Val swung 20–30 points between epochs. |
| 2. Staged soft→hard, b=8, 80 ep | Stable but no better: s 58.8, u 52.5. The hard phase stays at train loss 1.2–1.4. |
| Bug found on the way | Folded fp64 accuracy disagreed with the in-training eval (47.7 vs 64.5). Cause: exact ties in `topk` (CPU and CUDA break them differently) and coefficients exactly at the threshold that flip between fp32 and fp64. Fixed with a stable sort and an fp64 threshold. **Every reported number since then is the folded network.** The networks are fragile: flipping 1–5 coefficients moved one model's val from 52.9 to 36.9. |
| 3. Block-size sweep (staged) | s: b1 82.0, b2 80.7, b4 70.8, b8 ≈ 59–64. u: b1 69.7, b2 63.5, b4 57.7. Mixed (b4 on the 16-ch layers, b8 elsewhere): s 65.7, u 53.7. |
| 4. Recipe search at b=4 | Signed: hard-from-start QAT with Adam latents and weight decay 5e-5 gives **74.6**, vs 70.8 before. KD (−3.6), dense init, a soft first phase (−3.8) and other thresholds did not help. Unsigned: QAT was worse (48–57); staged + KD gives **59.5–60.6** (62.8 at 200 ep). |
| Ceiling check | A **real-valued** top-2 b=4 model reaches only 75.3 (signed) and 60.6 (non-negative), and real block-circulant b=8 with all 8 shifts reaches about 74. The ±1 / 0/1 quantization therefore costs almost nothing. **The loss comes from the QC structure itself.** |
| 5. Matrix view chw vs hwc | s4 70.0 vs 74.6 (−4.6); u4 58.1 vs 59.5–60.6; s8 63.7 vs 64.6. hwc kept. |
| 6. Width x2 (capacity probe) | s4 74.6 → 81.8 (+7.2), s8 64.6 → 77.0 (+12.4), dense 87.2 → 90.3 (+3.1). **QC ResNet-8 is capacity-limited.** |

**Why QC hurts this much here.** Inside a b x b block, every one of the b rows reuses the same ≤ 2 shift choices,
cyclically rotated. A block therefore has 2 degrees of freedom where a dense block has b². ResNet-8 has 16–64
channels and about 78k weights, so it has no redundancy to give up. The b=1 references, which have no QC sharing at
all, still lose 6 points (signed) and 19 (0/1) at this size. QC weights look viable only with more channels than
ResNet-8 has (row 6).

## Limitations

- **Seeds:** one seed per final model.
- **Additions:** the counts ignore savings from zero padding.
- **Dead channels in u2/u4/u8:** a few channels have a BN scale of about 0. Their requant multiplier is floored at
  2^-23 (`--wq`/floor in `nn/quant`), which makes them carry no signal. In u2 and u8, one conv0 row has all its ones
  on padded input channels.
- **Hardware:** the KUL GeMMX requant has 8 per-lane multipliers, not per-channel ones, so per-channel scales would
  need lane grouping or one call per group of 8 channels. `nn/compile` was not run on these models; hardware mapping
  was out of scope.
- **Export:** each model goes out as a load_h5-format `.npz` (`qc.export`) and int8 qparams from
  `nn.quant.quantize --params … --wgran channel --wq 1`.

## Reproduce

```bash
qc/fetch.sh                                   # CIFAR-10 + trained checkpoints -> /tmp/$USER/qc/final
qc/final.sh int8 s2                           # verify float QC, export, int8 via nn/quant, verify int8 QC
qc/final.sh stats                             # qc/results/*.md (after int8 for all six)
qc/final.sh train dense; qc/final.sh train u4 # retrain any model (u* use the dense run as KD teacher)
```
Ablation commands use the same `python3 -m qc.train` flags; see [`README.md`](README.md).

References: Fossorier, "Quasi-cyclic LDPC codes from circulant permutation matrices", IEEE T-IT 2004; Cheng et al.,
circulant projections, ICCV 2015; Ding et al., CirCNN, MICRO 2017; Deng et al., PermDNN, MICRO 2018; Li et al.,
Ternary Weight Networks, arXiv 1605.04711; Courbariaux et al., BinaryConnect, NeurIPS 2015; Ramanujan et al.,
edge-popup, CVPR 2020; Liu et al., Bi-Real Net (ECCV 2018), ReActNet (ECCV 2020); Shang et al., CReLU, ICML 2016;
Prabhu et al., Deep Expander Networks, ECCV 2018.
