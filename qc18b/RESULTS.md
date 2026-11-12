# qc18b results: CIFAR-100 QC ResNet-18 with 1-bit activations

**Task.** Take the qc18 QC ResNet-18 (signed b = 8, the configuration of the ASIC `qc18acc/`) to CIFAR-100. Make every
activation that feeds a QC conv 1 bit at inference, and lose ≤ 5 points (absolute) of test accuracy against the same
network with full-precision activations, over 2 seeds. Select on validation only and evaluate test once.

**Labels.** Every number is either **[M] measured** (from a run or a script in this repo) or **[E] estimated** (computed
or argued, not measured). Val is the fixed 45k/5k split (seed 0) of the CIFAR-100 training set. Test is the 10k test set.

## Headline (test %, 200 epochs, folded and verified network, test evaluated once per model)

| model | 1-bit QC-conv inputs | test s0 / s1 | mean | drop vs FP-act (s8kd) |
|---|---|---|---|---|
| dense, FP activations | – | 75.52 / 75.88 [M] | 75.70 | – |
| s8, FP activations | – | 63.72 / 64.43 [M] | 64.08 | – |
| **s8kd, FP activations (reference)** | 0 / 20 | 67.93 / 66.94 [M] | **67.44** | – |
| **e6: 1-bit, block 6 at 8 bit** | **17 / 20** | 63.33 / 63.64 [M] | **63.49** | **−3.95 ✓** (per seed −4.60 / −3.30) |
| bin: all 1-bit | 19 / 20 | 61.71 / 61.05 [M] | 61.38 | −6.06 ✗ |
| e6, integer reference (`int_bin.py`) | 17 / 20 | 63.22 / 63.44 [M] | 63.33 | −4.11 ✓ |
| bin, integer reference | 19 / 20 | 61.81 / 60.59 [M] | 61.20 | −6.24 ✗ |

- **Reference choice.** The reference is s8kd, the strongest FP-activation QC network in the same pipeline: same
  distillation from `dense_s0` and the same architecture and wiring. Against s8 (no distillation), e6 loses 0.6 points.
- **Target.** Met only with one multi-bit exception, block 6 (next section). The fully 1-bit network misses it by
  about 1 point.
- **Verification.** `verify_bin.py` checks the folded network:
  - All 20 convs per model are proved QC (≤ 2 signed shifted identities per 8×8 block).
  - BN is folded into a per-channel scale and bias.
  - Every second-conv threshold is folded to an integer compare on the integer accumulator.
  - The fp64 folded network agrees with the trained model on 5000/5000 val and 10000/10000 test images (0 differences). [M]
  - Files: `results/verify_*.txt`.
- **Val (selection metric).** e6 63.96 / 63.72, bin 62.38 / 61.94, s8kd 68.64 / 67.48. [M]

### Bit-widths at inference (e6)

| tensor | bits | feeds a QC conv? |
|---|---|---|
| image (stem input) | **8** (exception 1: the qc18acc stem already reads int8) | yes (stem) |
| block 0–5, 7 inputs of c1 / sc / c2 | **1** ({0,1}) | yes (14 convs + 2 shortcuts) |
| block 6 inputs of c1 / sc / c2 | **8** (exception 2; int8 in the integer reference) | yes (3 convs) |
| residual stream s_k (pre-ReLU), BN outputs before thresholds | int16 in the integer reference | no (thresholded or added) |
| integer accumulators | int32 | no |
| pool / FC input | multi-bit | no (FC is dense, as in qc18) |

The "bin" model has only exception 1.

### Inference cost of the exception [E]

- **Counts.** `opcount.py` counts signed additions per block from the hard QC weights (118.9 M per image [M]):

  | block | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | stem |
  |---|---|---|---|---|---|---|---|---|---|
  | share % [M] | 13.9 | 13.4 | 9.7 | 13.1 | 10.1 | 13.6 | 11.2 | 14.8 | 0.3 |

- **Costed model.** In a bit-serial datapath where an 8-bit input costs 8 passes of the 1-bit adder tree:
  - **e6** costs 0.885·1 + 0.115·8 ≈ **1.8×** the bit-ops of the all-1-bit network (stem included).
  - **qc18acc today** (int8 everywhere) costs 8×.
  - So e6 is about **4.4× cheaper than the current int8 qc18acc**, and about 1.8× more expensive than "bin". [E]
- **No new operators.** The exception adds no multipliers, convs or extra tensors. The block-6 inputs keep the
  int8 RELU requant path that qc18acc already has.

## Pipeline (what was built)

`qc18b/` imports `qc18/` and never copies or edits it.

| file | role |
|---|---|
| `data.py`, `c100.py`, `train.py`, `verify.py`, `final.sh` | CIFAR-100 port (runtime patch of `qc18.train` / `qc18.verify` globals), FP-activation finals dense / s8 / s8kd |
| `binact.py` | `BinAct` 1[x > t_c] (learnable per-channel threshold, clip / approx / bussgang / stein STE, `--ste-scale K`), `binarize()`; options `--preact`, `--arch bireal`, `--stem-therm`, `--fp-blocks`, `--abits`, `--xfb`, `--prog` |
| `train_bin.py` | trainer: own flags, then `qc18.train.main()` |
| `bnopt.py`, `distill.py` | Adam for BN / thresholds; QC-teacher feature / logit / attention distillation (AuxInject) |
| `verify_bin.py` | folded verification + QC proof (single test evaluation) |
| `int_bin.py` | integer reference (style of `qc18/int8.py`) |
| `opcount.py` | additions per block |
| `final_bin.sh` | final recipes `bin` / `e6` (train / verify / int) |
| `diag/*.py`, `diag/results/*.md` | every measurement quoted below |
| `SURVEY.md` | BNN literature survey (2016–2026), inference cost classified against qc18acc |

## Final recipe (e6)

```
qc18b/final.sh train dense 0 && qc18b/final.sh train s8kd {0,1}         # FP-activation finals (teacher, init)
qc18b/final_bin.sh train e6 {0,1}; qc18b/final_bin.sh verify e6 {0,1}; qc18b/final_bin.sh int e6 {0,1}
```

- **Activation.** The QC conv input is b = 1[x > t_c] ∈ {0,1}, with a learnable per-channel threshold t_c.
  - Because BN follows every conv, any activation scale is absorbed into the BN fold, so {0,1} needs no scale.
  - The threshold for the second conv of each block folds into the integer accumulator compare 1[sign(g)·acc ≥ T].
- **Where it binarises (`--preact`).** The block-input binarisation reads the pre-ReLU block sum s. The identity path
  keeps relu(s). With FP activations the network computes exactly the same function as qc18 (tested, max diff 0).
- **Gradient.** Clipped straight-through, |x − t| < 1, scaled by K = 0.6. The threshold gradient is −Σ of the same.
- **Training.** Initialise from the FP-activation s8kd checkpoint of the same seed. Then 200 epochs of the qc18 s8kd
  recipe: SGD lr 0.1 for BN / thresholds / FC, AdamW 1e-2 with wd 0.1 for the QC latents, cosine, KD 0.5 at T = 4
  from `dense_s0`.
- **Exception.** Block 6 keeps ReLU activations (`--fp-blocks 6`).

## The maths of the two training defects we found and fixed

**D1, exploding backward gain through binary layers** (collapse of every naive run: val 13–23 % after 60 epochs [M]).

- **Gain model.** For z = BN(W·f(x)) with x ≈ N(0,1), the backward gain of one layer is ≈ γ·rms(f′)/σ_f.
  - ReLU: 0.71/0.58 ≈ 1.2.
  - Clipped STE onto {0,1} at threshold 0: rms(f′) = √P(|x| < 1) = 0.83 and σ_b = 0.5, so gain ≈ 1.65 [E].
- **What we saw.** Gradients at the binary layers grew ×2.2–2.4 per binary conv [M]: 600× from block 7 to block 0 at
  step 50, before any threshold moved.
- **Collapse chain.**
  1. SGD steps on the early thresholds and BN shifts scaled with that gradient; the threshold std went 0.2 → 4.4 in 350 steps.
  2. Every element left the STE window; the pass fraction went 0.85 → 0.002.
  3. 94 % of block-0 channels became constant, which cut both the information and the gradient. [M]
- **Causal tests** (30 epochs [M]):

  | run | val |
  |---|---|
  | clip | 25.5 |
  | thresholds frozen (the BN shift is an equivalent threshold) | 23.7 |
  | **K = 0.43** | **48.8** (gain/layer 2.23 → 1.27) |

- **Sharp edge.** K = 0.6 trains; K = 0.8 collapses (27.4) [M].
- **Training BN and thresholds with Adam** removes the collapse at K = 1 (59.2 val, 100 epochs) [M], but K = 0.6 is
  still better under Adam (60.2) and under SGD (61.7).
  - So attenuating the binary path helps beyond stability. Weighting each gradient path by K^(binary hops on it)
    favours the exact FP identity path over STE-approximated paths.
- **Estimators tried for D1** (both failed for a measured reason):
  - **Bussgang** (a_c = Cov(b,x)/Var(x)): exactly 0 on constant channels, so they can never revive, and huge on
    near-constant ones. Val 1.4. [M]
  - **Stein** (a_c = φ(z)/σ): ∝ 1/σ_c, so BN γ → 43. Val 24.8. [M]

**D2, the ReLU atom.**
- The block-input binarisation originally read relu(s), which has 30–87 % of its mass at exactly 0 [M].
- With t_c initialised at 0, any t_c < 0 (we measured −1e-6) maps the whole atom to 1, so the channel goes constant.
  48 % of block-input channels were constant at step 50, against 0 % with t frozen at exactly 0. [M]
- Fix: threshold the pre-ReLU sum (`--preact`). Constant channels then fall to 0.000 [M].
- Accuracy did not change at 30 epochs (50.6 vs 48.8 at K = 0.43 / 0.6), so D2 was real but was not the bottleneck.

## Where the remaining gap comes from (measured diagnosis, all-binary I0 vs FP s8kd_s0)

The diagnosis compares I0 (all-binary, 200 epochs, initialised from s8kd_s0) with s8kd_s0, using `diag/diagnose.py`,
`recover.py`, `attn.py` and `bits.py`.

- **Underfitting, not overfitting.** Train accuracy is 76.1 vs 90.7 and train CE 0.88 vs 0.32. The per-class gap
  does not depend on class difficulty (corr −0.09). [M]
- **The loss is distributed.** Linear-probe val accuracy on the block outputs falls behind from block 0 (−4.1) and
  reaches −8.5 at block 7. No single stage transition is uniquely lossy. The downsampling shortcut on 1-bit input has
  only 25–319 distinct integer outputs (QC: ≤ 2 of every 8 input channels per output), but the FP net's shortcut
  adds little information either. [M]
- **Each 1-bit view loses some information.**
  - It loses 0.2–4.4 probe points against the FP stream it reads.
  - One bit recovers R² 0.32–0.62 (median 0.54) of the pre-threshold signal; the 3×3 neighbourhood the next conv sees
    recovers 0.59.
  - Channels are not starved: entropy median 0.82 bit, effective rank 1.6–3.8× that of the FP signal. [M]
- **Gradient flow is healthy** for all 200 epochs (g_out within 4× across depth, pass 0.16–0.77). [M]
- **The decisive decomposition (30 epochs, val, all-binary 50.6 [M]).** Give one block FP activations:

  | block 6 | val | gain |
  |---|---|---|
  | FP forward + exact backward | 57.1 | +6.5 |
  | FP forward + STE-shaped backward | 52.7 | +2.1 |
  | binary forward + ReLU backward | 26.9 | collapses |

  Block 4 gives 55.1 / 50.2 / 30.2.
  - About two-thirds of an FP block's gain needs its forward and backward to be consistent, which no binary forward
    has. The STE error compounds over the 16 binary hops.
  - This also explains why 2-bit activations in blocks 6–7 recover only +2.5 against +7.9 for FP [M].
  - A wider forward alone is not what an FP block provides.

## Ablations and failures (val %, seed 0 unless noted, all [M])

| change | epochs | val | reference | mechanism / reading |
|---|---|---|---|---|
| naive BinAct (clip / approx / from FP init) | 60 | 23.4 / 13.3 / 19.3 | FP 66.7 | D1 collapse |
| per-conv FP shortcuts (Bi-Real wiring, extra adds) | 30 / 200 | 53.8 / 61.2 | 50.6 / 60.9 | +3 at 30 ep, gone at 200; dropped (hardware cost) |
| thermometer-coded stem (16 / 32 levels, 1-bit stem input) | 30 | 51.4 / 51.8 | 53.8 (8-bit stem) | −2, +~10 % ops [E]; dropped |
| init from FP s8kd | 30 / 200 | 58.5 / 62.4 | 50.6 / 60.9 | the gain mostly vanishes: a fresh optimiser at lr 0.1 erases any init (the FP-activation fine-tune control also flips 84 % of QC blocks and drops to 54 % in epoch 0) |
| FP-init, peak lr ×1 / ×0.5 / ×0.2 | 100 | 61.7 / 61.2 / 61.4 | – | 50–76 % of QC blocks flip in epochs 1–10 regardless |
| STE scale K 0.8 / 1.0 (SGD) | 100 | 27.4 / 17.7 (stopped early) | 61.7 | D1 edge |
| Adam for BN + thresholds, K 1.0 / 0.6 | 100 | 59.2 / 60.2 | 61.7 | see D1 |
| per-block feature KD (MSE) from the QC FP teacher | 79 of 100 | 56.4 | trajectory = ref | the target is infeasible (aux loss plateaus at 0.6) |
| logit KD from the QC FP teacher instead of dense | 85 of 100 | 58.5 | trajectory = ref | – |
| Real-to-Binary attention matching (β 30) | 100 | 60.2 | 61.7 | attention loss driven to the flip-reference level, no gain: attention mismatch is not the cause |
| progressive stochastic binarisation (StoMPP-like) | 100 | 39.0 | 61.7 | the net learns a magnitude-coded mixture that is not realisable in binary (as qc18's weight homotopy did) |
| 2×2 ordered-dither thresholds | – | R² 0.593 → 0.616 | – | premise not supported; not trained |
| 2-bit activations in blocks 6–7 | 30 | 53.1 | 50.6 (FP 6–7: 58.5) | see the decomposition above |
| FP-activation block 4 / 5 / 6 / 7 alone | 30 | 55.1 / 56.1 / 57.1 / 53.4 | 50.6 | block 6 best gain per cost → e6 |
| STE first-order fidelity (random directions) | – | corr ≈ 0.02–0.3 | FP 1.00 | inconclusive: the finite-difference target is not reproducible across batches (corr ≈ 0) |

## Integer reference (`int_bin.py`)

- **Arithmetic.** int8 image as in `qc18/int8.py`, integer QC weights (re-proved QC), int32 accumulators, the
  second-conv threshold as an integer accumulator compare, int16 fixed-point residual stream (per-tensor scale from
  train[:2000]), integer block-input thresholds T = floor(t/S), int8 ReLU requant in block 6, integer pool, FC as qc18.
- **Accuracy.** Within 0.6 points of the folded fp64 network. Test: e6 63.22 / 63.44, bin 61.81 / 60.59. [M]
- **Not pointwise equivalent.** 18–23 % of val images change argmax [M]:
  - The binary network amplifies tiny perturbations; 3–13 % of the bits in deep layers flip.
  - Int8 input rounding alone seeds most of it. An exact stem output with only int16 stream rounding still changes
    749 images.
  - So the integer model is its own deterministic network of near-equal accuracy, not a bit-exact image of the float
    one. qc18's int8 path was nearly pointwise (≤ 0.3 points, same images); this one is not.
- **The same sensitivity in floating point.** The all-binary I0 network's fp32 and fp64 forwards disagree on 688/5000
  val images (accuracy differs by 12 images) [M]. Deployment should define the integer model as the reference.

## Honest assessment

- **Target.** Met (−3.95 test points, both seeds ≤ 5), but only with a 3-conv 8-bit exception that costs about 1.8×
  the bit-ops of a fully binary net [E]. That is still about 4.4× cheaper than the int8 qc18acc [E]. The fully 1-bit
  network misses by about 1 point (−6.06).
- **Novelty.**
  - The training recipe uses known parts (clip STE, learnable thresholds ≈ RSign without the extra op, KD, FP init).
  - The specific findings are measured: D1's gain mechanism and its sharp K edge, D2's atom pathology, the failure
    mechanisms of Bussgang and Stein, and the forward/backward decomposition.
  - The decomposition says the residual binary-activation gap here is mainly a gradient-consistency defect, not a
    capacity defect of the forward. No zero-cost estimator we derived or found fixed it. That is the open problem
    this work leaves.
- **Threats.**
  - Only 2 seeds; the per-seed drops are −4.60 and −3.30, so the margin to 5 is thin for seed 0.
  - All 30- and 100-epoch ablations are single-seed on val, and differences under about 1 point are noise.
  - The exception (block 6) was chosen on 30-epoch val.
  - The integer reference is not pointwise equal to the float model.
  - The cost figures are bit-op estimates, not ASIC measurements; `qc18acc/` was not changed.
- **Not done.**
  - The thermometer stem was dropped on hardware cost, so the image stays 8-bit.
  - No 1-bit training of the stem.
  - No co-design with the ASIC agent of a mixed 1-bit / 8-bit datapath.

## Reproduce

```
qc18b/final.sh train dense 0; qc18b/final.sh train s8kd 0; qc18b/final.sh train s8kd 1
qc18b/final_bin.sh train e6 0; qc18b/final_bin.sh verify e6 0; qc18b/final_bin.sh int e6 0     # and seed 1, NAME bin
python3 -m qc18b.test_binact; python3 -m qc18b.test_distill; python3 -m qc18b.test_bnopt
python3 -m qc18b.opcount /tmp/$USER/qc18b/final_bin/e6_s0/best.pt
```

The final runs of record were trained in `/tmp/root/qc18b/{exc200,init200}/` with the same arguments as
`final_bin.sh` (their `verify.txt` / `intbin.txt` are copied to `qc18b/results/`).
