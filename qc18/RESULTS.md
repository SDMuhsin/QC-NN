# qc18 results: quasi-cyclic ResNet-18 on CIFAR-10

All QC numbers are for the **verified folded network**:
- BN is folded into a per-output-channel scale and bias.
- Every conv's GEMM matrix `[cout, kh*kw*cin]` is decomposed exactly into b×b blocks. Each block is either zero or a sum of ≤2 distinct cyclically shifted identities.
- The fp64 folded network is then evaluated. It matches the trained fp32 model to within +0 images in every run.

"signed" means entries are in {−1, 0, +1}. This is the stated extension, equal to strict QC on `[x; −x]`. "strict" (`u*`) means entries in {0, 1}. The FC layer is dense.

How models were selected and tested:
- Training uses a fixed 45k/5k train/val split (seed 0). All selection was made on val.
- The 10k test set was evaluated **once**, on the final checkpoints (`verify.txt`, `int8.txt`).
- The dense reference uses the same pipeline: 200 epochs, bs 128, crop+flip, SGD/cosine for BN/FC, bf16.

Every number below can be reproduced from `qc18/final.sh`, `qc18/table.py` and `qc18/fetch.sh`.

## Headline (test %, 200 epochs, mean ± std over 2 seeds)

| model | entries | b | float test | int8 test | gap vs dense | weight storage vs dense int8 | additions vs dense MACs |
|---|---|--:|--:|--:|--:|--:|--:|
| dense | real | – | **94.91 ± 0.01** | – | – | 1 | 1 |
| s2 | signed | 2 | 92.41 ± 0.71 | 92.38 ± 0.83 | −2.50 | 0.1875 | 0.66 |
| s2kd | signed | 2 | **92.66 ± 0.02** | 92.67 ± 0.07 | **−2.25** | 0.1875 | 0.66 |
| s4 | signed | 4 | 90.48 ± 0.11 | 90.37 ± 0.06 | −4.43 | 0.0625 | 0.41 |
| s4kd | signed | 4 | **91.46 ± 0.14** | 91.44 ± 0.05 | **−3.45** | 0.0625 | 0.41 |
| s8 | signed | 8 | 90.45 ± 0.24 | 90.37 ± 0.25 | −4.46 | 0.0195 | 0.23 |
| s8kd | signed | 8 | **91.38 ± 0.14** | 91.27 ± 0.09 | **−3.53** | 0.0195 | 0.23 |
| u2 | strict 0/1 | 2 | 87.06 ± 0.06 | 86.95 ± 0.18 | −7.85 | 0.125 | 0.16 |
| u4 | strict 0/1 | 4 | 85.77 ± 2.02 | 85.45 ± 1.93 | −9.14 | 0.047 | 0.13 |
| u8 | strict 0/1 | 8 | 85.43 ± 1.07 | 85.41 ± 1.12 | −9.48 | 0.016 | 0.09 |

Notes on the table:
- With 2 seeds, the std is only indicative. Per-seed numbers are in `python3 -m qc18.table`, and per-layer storage/additions in `qc18/results/`.
- `*kd` uses distillation from a dense teacher (`dense_s0`), which costs one extra dense training run. The dense reference itself is not distilled.
- int8 is integer-exact:
  - weights are exactly sign(s_c)·M, with M the QC matrix, re-proved QC;
  - per-channel scale |s_c|, per-tensor activation scales, int32 accumulation, fixed-point requantization.

  int8 costs ≤0.3 points everywhere.
- Storage counts the QC index/sign bits plus the per-channel scale and bias, compared against dense int8 weights. Additions count signed adds per output, compared against dense MACs. Both exclude the FC layer (`stats.py`).
- The strict 0/1 models vary strongly between seeds at b=4 and b=8: u4 gave 84.34 / 87.20.

## Method (what the final recipe is)

- **Parametrisation.** Each b×b block of each conv has a latent vector θ ∈ ℝ^b over shifts, i.e. a block-circulant latent.
- **Hard projection.** z = θ/α_r, where α_r is the mean over each block row of every block's mean top-2 |θ|.
  - Signed: keep the top-2 |z| with |z| > ½, with value sign(z).
  - Unsigned: keep the top-2 z > ½, with value 1.

  This is the exact Euclidean projection onto α·V (V = the set of feasible blocks), with a TWN-style threshold (`qcconv.py`; brute-force checked in `test_qcconv.py`).
- **Gradient.** Straight-through (identity) through the projection. The per-row scale comes from the following BN.
- **Optimizer for the latents: AdamW, lr 1e-2, decoupled wd 0.1.** This is the single most important choice. The hard map is invariant to rescaling θ per block row, so only the *angular* update rate matters. Without weight decay, Adam lets ‖θ‖ grow, the effective angular lr decays, and the structure freezes early. Decoupled wd yields an equilibrium norm, i.e. a constant effective rate (cf. rotational equilibrium; Kosson et al.; van Laarhoven; Helwegen et al.'s "latent weights do not exist").
- **Strict 0/1 additions:**
  - BN γ initialised with random ±1 signs (`--bn-sign 1`), so channels can realise negative effective weights.
  - Sparse 2-hot init (`--qinit-k 2`).
- **Distillation** (`*kd`): loss = ½ CE + ½ T²·KL(T=4) against the dense teacher.

## Ablations (60 epochs, val %, b=8 signed unless noted)

| change | val | effect |
|---|---|---|
| final recipe (STE, AdamW 0.1) | 90.66 / 90.44 / 90.42 (3 seeds) | – |
| Adam, no wd | 88.08 / 88.46 / 88.42 | −2.2 |
| fixed-norm sphere latents (3 radii) | 86.4 / 88.7 / 88.9 | −1.6 to −4 |
| SGD with equilibrium wd (lr/wd/init variants) | 69.2–89.3 | worse |
| exact Gibbs Jacobian estimator, τ=1 | 90.54 / 90.22 | = STE |
| Gibbs, τ=0.5 | 91.34 (1 seed), not reproduced | noise |
| homotopy relaxed→hard, Gibbs mean | 80–87.7 | collapses at switch |
| homotopy relaxed→hard, linear ramp | 90.0 / 89.9 | = STE or slightly worse |
| + distillation | 91.04 / 91.52 | **+0.8** |
| unsigned b=2: no fix / ±1 BN γ / 2-hot init / both | 79.4 / 84.7, 82.8 / 81.6 / 84.5, 84.2 | +5 |

**Where the gap comes from** (60 epochs, val, 2 seeds; same pipeline with the constraint relaxed one step at a time):

| | b=2 | b=4 | b=8 |
|---|--:|--:|--:|
| dense | 94.4 | 94.4 | 94.4 |
| real-valued block-circulant | 92.3 | 91.6 | 91.4 |
| real-valued, top-2 shifts per block | – | – | 91.6 |
| signed QC (±1, ≤2 shifts) | 92.4 | 90.7 | 90.5 |

So at b=8:
- the **circulant structure itself costs ~3 points**;
- restricting each block to 2 shifts costs ~0;
- ±1 values cost ~0.9 (~0 at b=2).

**Any training method for this QC format is therefore bounded by about 0.9 points of possible gain at b=4 and b=8, and essentially 0 at b=2.** Distillation already exceeds the non-distilled real-circulant ceiling.

## Mechanistic diagnosis of training (what we looked for and what we found)

A better estimator than STE was the goal. Before building one, we measured where STE might be failing. Tools are in `qc18/diag/`; runs are s8, 60 epochs unless noted.

1. **STE's first-order prediction is accurate.** For single-tile moves, the sign of the predicted ΔL agrees with the exact ΔL 95% of the time. A quadratic fit of the exact loss along moves has correlation ≈0.99 and curvature/linear ratio ≈0.12–0.2. There is no bias or curvature defect for an estimator to fix (`local_model.py`).
2. **Latent magnitudes carry no information.** Using kept = z (real values instead of ±1) in the forward drops val to 18–32%. The latents act purely as switch evidence (`magnitudes.py`).
3. **The structure churns heavily, and the churn is how training learns:**
   - 63% of tiles change per epoch until epoch ~40, and ~45% of changes revert within 100 steps.
   - The flips of one step are individually near coin flips: 52–56% lower the loss, with median z −0.15 to −0.6. With BN recalibrated, their joint effect is ≈ 0 (`coupling.py`).
   - Yet freezing the structure at epoch 15/30/45 of 60 costs −5.3 / −3.4 / −1.6 val (2 seeds each; `freeze.sh`). Half the tiles still change after epoch 45.

   Suppressing noisy switching therefore has no measured justification. Flips are the only conv degrees of freedom, and the slow drift in them is the learning.
4. **Final structures are not single-move optimal, but that does not limit val:**
   - 27–55% of tiles have a significantly loss-reducing single move (z < −3 across 10 train chunks; `evidence.py`).
   - Verified greedy local search with random candidates accepted 2080 moves. It cut held-out train loss 0.0386→0.0334, but val moved only 91.22→91.52, within noise (1 seed; `polish.py`).
   - Top-ranked moves concentrate on a few stem rows. Applied together, they interfere positively in every pair. Without BN recalibration, they inflate one output row ~3× against frozen BN statistics, a measurement artifact we found and fixed in our own tools (`diag/common.py: recal_v`).

   The converged gap is a generalisation/capacity gap, not a search failure.

## What was tried and failed, and why

- **Exact Gibbs Jacobian estimator.** We enumerated V and computed the exact softmax-relaxation Jacobian Cov_p(v)/τα. Result: = STE (90.64 vs 90.51, 3 seeds). By finding 1, STE's first-order information is already accurate, so a more exact relaxation has nothing to correct.
- **Homotopy (relaxed forward annealed to hard).** The Gibbs-mean forward collapses when switched to hard: the relaxed network uses non-vertex weights that are not realisable. The linear ramp at best ties STE.
- **Fixed-norm (sphere) latents.** These fix the effective rate but remove the adaptive equilibrium; −1.6 to −4.
- **SGD-equilibrium latents.** Very sensitive to init scale and wd; never beat AdamW.
- **Polytope-proximal (Fenchel–Young/SparseMAP-style) estimator.** Designed but abandoned untested. The diagnostics above left it no defect to fix (first-order accurate, gap structural), so a one-shot try would have been a blind guess.
- **Post-hoc verified polishing and structure freezing.** See findings 3–4.

## Relation to prior work, and honest novelty

The recipe combines known ingredients:
- block-circulant weights (CirCNN, Ding et al. 2017; PermDNN, Deng et al. 2018);
- ternary/threshold projection (TWN, Li et al. 2016) and STE (BinaryConnect; Bengio et al. 2013);
- N:M-style sparse-structure training with STE (SR-STE, Zhou et al. 2021);
- weight-decay/effective-learning-rate equilibrium for scale-invariant weights (van Laarhoven 2017; Hoffer et al. 2018; Kosson et al. 2024), and latent weights as switch inertia (Helwegen et al. 2019, Bop);
- `[x; −x]` signed-to-unsigned reduction (CReLU, Shang et al. 2016);
- distillation (Hinton et al. 2015).

What is specific to this work:
- **The format itself.** "≤2 shifted identities per b×b block, ±1 / 0-1 entries" is a sparser and more hardware-friendly constraint than CirCNN's real circulants. We have not found it trained end-to-end in the literature.
- **The exact Euclidean projection onto α·V** for this format, and an exact enumerated Gibbs Jacobian for it. Both are correct but give no accuracy gain.
- **An exact QC verifier** and an **integer-exact int8 pipeline** proving the deployed weights are QC.
- **The measured decomposition of the accuracy gap** (circulant ≈3 pts vs ±1 ≈0.9 pts at b=8), and the **mechanistic negative result**: STE is first-order accurate here, so no estimator can recover more than ≈0.9 pts.

We do **not** claim a new, provably optimal estimator. The evidence says the remaining gap is structural, not an estimation defect.

## Does the gap justify QC hardware?

- **b=8 signed** is the efficient point: about 51× less weight storage than int8 dense, and multiplier-free convs with about 23% as many additions as dense MACs. The cost is **−3.5 test points with distillation** (91.4 vs 94.9). It dominates b=4: same accuracy, 3× less storage.
- **b=2 signed** costs −2.3 points for only 5× storage reduction and 66% of dense op count. A conventional ternary or low-bit dense ResNet-18 is reported to lose ≈1 point on CIFAR-10 at ~4× storage reduction vs int8 (literature, not measured here), so b=2 is not compelling.
- **Strict 0/1** costs 8–10 points and is not competitive. Use the signed form, i.e. `[x; −x]` inputs, at 2× input width.

Recommendation: QC hardware is justified **only for targets where ~3.5 points of CIFAR-10 accuracy can be traded for ~50× weight storage and multiplier-free convs**, using signed b=8 with distillation. The ~3 points lost to the circulant structure are not recoverable by better training. The levers that remain are architectural (e.g. width, or keeping the stem/first layer dense), which we did not explore within this budget.

Limitations:
- Only 2 seeds per configuration.
- The 60-epoch ablations are on val only.
- There is no measured ternary-dense baseline.
- Single dataset and architecture.

## Reproduce

```
qc18/final.sh train s8kd 0 && qc18/final.sh verify s8kd 0      # any NAME in final.sh, seed 0/1
CUDA_VISIBLE_DEVICES=0 python3 -m qc18.int8 /tmp/$USER/qc18/final/s8kd_s0/best.pt --test
python3 -m qc18.stats /tmp/$USER/qc18/final/s8kd_s0 ; python3 -m qc18.table
qc18/fetch.sh            # or QC18_TARBALL=/path/qc18-final.tar.gz qc18/fetch.sh
```
