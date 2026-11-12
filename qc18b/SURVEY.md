# BNN (1-bit activation) literature survey for qc18b

Scope: methods that binarize activations (W1/A1 or real/A1), 2016–2026. We read them against the qc18b setting: a QC ResNet-18 on CIFAR-100 whose non-stem conv inputs are {0,1} with per-channel thresholds. The FP-activation model gets 68.6 val and the binary model 62.4. The binary model underfits (train 76 vs 91), and the loss is spread across all 16 binarizations.

Verification key:
- **[V]** = read in the paper PDF or in the official code during this survey (PDFs fetched from arXiv and checked with pdftotext).
- **[S]** = secondhand: from memory, a search snippet, or another paper's table. Not checked against the source.

Cost key, against the ASIC constraint:
- **ZERO** = the inference graph is identical to ours, or reduces to a per-channel affine plus a threshold.
- **COST: X** = needs X at inference.

## 1. Method table

| Method (venue, year) | Core idea | Inference cost | ImageNet R18 top-1 (W1/A1) | CIFAR-100 | What it does for activations / act-gradients / training |
|---|---|---|---|---|---|
| XNOR-Net (ECCV 2016) [1] | Analytic scales α (weights) and K (activations, spatial mean of \|x\|) | COST: K map per input (real multiply). α is foldable | 51.2 [V, via R2B Tab.2] | – | Activation scale K. Plain sign/clip STE |
| Bi-Real (ECCV 2018) [2] | Real-valued shortcut around **every** binary conv; ApproxSign gradient; init from tanh/clip FP model | COST: an extra multi-bit add and a live residual tensor per conv. ApproxSign and init are ZERO | 56.4 [V] | 63.51 (Bi-Real-18) [S, NeuroBlend table] | Piecewise-quadratic act gradient 2−2\|x\| (ReActNet code `BinaryActivation`). FP pretrain with clip(−1,1) |
| Real-to-Binary (ICLR 2020) [3] | Strong Baseline plus progressive teacher-student, block-output attention matching, and data-driven gating | Gating: COST (SE-like branch). Attention matching, progressive TS and two-stage: ZERO | 65.4 [V] | **Yes, R18, see §3** [V] | 3-step TS: FP→FP with tanh soft-binarized activations→binary-act/real-W→binary-all. Adam. WD 1e-5 then 0. Mixup "crucial" on C100. 350 ep on C100 |
| ReActNet (ECCV 2020) [4] | RSign (learnable per-channel threshold), RPReLU, **distributional loss** (KL to a real teacher, replaces CE), two-step | RSign: ZERO (we already have it). RPReLU: COST (shift/PReLU on the multi-bit stream). Loss and two-step: ZERO | 65.9 (R18) [V, via SURGE Tab.3]; 69.4 (MobileNet-based ReActNet-A) [V] | 70.76 (ReActNet-18) [S] | Two-step (binary act first, WD 1e-5→0). KL-only loss gives +1.4 ImageNet [V] |
| AdamBNN, "How do Adam and training strategies help BNNs" (ICML 2021) [5] | Adam over SGD (less activation saturation); WD on latent weights hurts flip stability | ZERO (pure training) | 70.5 (ReActNet-A arch) [V] | – | Saturation: 38.6% of first-conv inputs fall outside the clip window with SGD, 23.8% with Adam [V]. WD scheme 5e-6→0. BA-first then BW (BABW) 63.23 vs BWBA 60.17 [V] |
| IR-Net (CVPR 2020) [6] | Libra-PB (balanced, standardized weights; power-of-2 scale); EDE (tanh-shaped act/weight gradient, annealed from STE to sign) | Libra-PB: bit-shift on weights (weight-side, not applicable to QC). EDE: ZERO | 58.1 [S] | – (C10 only) [V: no C100 mention] | EDE: g = k·t·(1−tanh²(tx)), with t annealed 0.1→10 [S] |
| RBNN (NeurIPS 2020) [7] | Bi-rotation of latent weight vectors, plus a training-aware sign approximation | ZERO for a dense BNN. Rotation conflicts with QC structure | 59.9 [S] | – | Act gradient F(x)=k(−sign(x)t²x²/2+√2tx) with k,t scheduled [S] |
| FDA-BNN (NeurIPS 2021) [8] | Fourier-series gradient of sign, plus a training-time noise-adaptation module | ZERO (module only during training [V abstract]) | 60.2 [V] | – | Act-gradient estimator |
| ReCU (ICCV 2021) [9] | Rectified clamp unit revives "dead" latent weights | ZERO, weight-side | 61.0 [S, via BiPer text]; 66.4 two-step [V, via SURGE] | – | Weight-side only |
| SiMaN (TPAMI 2022/24) [10] | Weights in {0,+1} by sign-to-magnitude (entropy maximization) | ZERO, weight-side | 60.1 [S] | – | Relevant only as a {0,1} encoding precedent |
| Si-BNN (AAAI 2020) [11] | **{0,1} activations** (sparse), trainable backward thresholds | ZERO for a {0,1} ASIC | 58.9 [S, snippet] | – | Closest precedent to our {0,1} activation encoding |
| Kim et al., unbalanced activation (WACV 2021) [12] | Shift the binarization threshold so activations are unbalanced; argues **threshold training via backprop is ineffective because BN bias already learns it** | ZERO | +gain on XNOR/Bi-Real [S, number not read] | – | Global threshold shift (best around 0.6–2.0). Pick the shift from first-epoch train accuracy [V] |
| Ding et al., distribution loss (CVPR 2019) [13] | Loss on per-channel pre-binarization moments: penalize degeneration, saturation, gradient mismatch | ZERO (training loss only) | AlexNet 47.9 [V, README] | **ResNet(-20, wide) C100: 60.40→68.17, 64.57→71.53, 66.07→73.42 (+7.0 to +7.8)** [V] | Lowers *training* loss (aimed at underfitting). λ=2. Turned off after `distr_epoch` |
| AdaBin (ECCV 2022) [14] | Per-layer learned binary set {β−α, β+α} for weights and activations, plus a Maxout nonlinearity | Activation set: an affine of {0,1}, foldable into BN except at zero-padding borders. Maxout: COST | 66.4 [V] | – | Equivalent to our {0,1}+threshold+BN on the activation side |
| MeliusNet (2020) [15] | Dense + Improvement blocks to raise quality and capacity | COST (architecture, more channels) | 63.6 (MeliusNet-22) [S] | – | – |
| INSTA-BNN (ICCV 2023) [16] | Instance-aware threshold from per-sample mean/var/skewness | COST (per-instance statistics at inference) | 68.5 (INSTA-BNN+, ReActNet-based) [V] | – | Threshold depends on the input |
| PokeBNN (CVPR 2022) [17] | PokeConv: multiple residuals, DPReLU, SE-like; ACE cost metric | COST | 75.6 (1.4x variant) [V] | – | – |
| BNext (arXiv 2022 / TMLR 2023) [18] | Info-recoupling + ELM attention; diversified consecutive KD; teacher selection | COST (attention/SE branches, multi-shortcut) | 68.4 (BNext-18) [V] | **BNext-18 ≈72.2 test (5-run mean)** [V, parsed Tab.10, layout garbled] | Too strong a teacher early hurts; uses consecutive teachers [V] |
| ReSTE (ICCV 2023) [19] | Rectified STE: power-function estimator that trades estimation error against gradient stability | ZERO | 60.88 [S] | – (C10) | Act and weight estimator |
| BiPer (CVPR 2024) [20] | Square-wave (periodic) binarization forward, sine-wave gradient | ZERO | 61.4 [S, repo] | – (C10) | Estimator |
| Schoenbauer et al. (arXiv 2024) [21] | Theory: custom **weight** gradient estimators ≡ STE under Adam (small learning rate) | n/a | – | – | Implies weight-STE shapes are moot for our AdamW θ |
| Hyperbolic BNN (TNNLS 2025) [22] | Hyperbolic latent-weight optimization; polynomial activation estimator | ZERO [S] | [S] | – | – |
| StoMPP (arXiv Jan 2026) [23] | Layer-wise stochastic masked progressive binarization. Backprop only through not-yet-frozen elements (no STE) | ZERO | +1.3 over its STE baseline [V abstract] | **R18 BNN +4.7 over BinaryConnect-style STE** (weak baseline: STE at R50 26.7) [V] | Progressive per-element and per-layer binarization |
| SURGE (ICML 2026) [24] | Training-only FP auxiliary conv per binary layer: out = f_b − λf_a.detach() + λf_a (forward exact), with adaptive λ | ZERO (branch dropped at inference) [V] | 66.7 (two-stage) vs ReActNet 65.9 and RBONN 66.5 [V] | – (C10 R20: 87.4→88.0) [V] | Adds FP-path gradient to each binary layer. No public code found |
| CBCN, circulant binary conv (CVPR 2019) [25] | Circulant filters (rotated copies of each kernel) to diversify binary features | COST (about 4× feature channels) | 61.4 [V abstract] | Yes (C100 table, not extracted) | Only circulant+BNN precedent found. Circulance there *adds* capacity, unlike our QC sparsity |
| Sub-bit BNN (ICCV 2021) [26] | Binary kernels restricted to a learned per-layer subset (<1 bit/weight), also with binary activations | ZERO vs BNN (fewer weight bits) | moderate drop vs BNN [S] | – | Closest "structured binary weights + binary activations" precedent |

**On "ResNet-18"**: almost every ImageNet BNN "ResNet-18" number is a Bi-Real topology. It has a real shortcut around every conv, real-valued (FP) downsample, and PReLU/RPReLU. Under our constraint each of these is **COST** (GDNSQ 2025 [27] makes the same caveat). Treat the absolute numbers as upper bounds that use extra multi-bit tensors.

**{0,1} vs ±1 activations**:
- With a per-channel BN affine and a threshold, the two encodings are equivalent up to a per-output-channel constant: conv(W, 2b−1) = 2·conv(W,b) − ΣW.
- The equivalence breaks only at zero-padded borders. There, {0,1} padding means "off", while ±1 padding with 0 behaves like a ternary input. AdaBin's activation set exploits this same affine freedom [V].
- No controlled head-to-head on the same architecture was found. Si-BNN (ImageNet, {0,1}, 58.9) [S] and the 2017 speech study (AMI WER 27.5 for {0,1} vs 30.1 for ±1) [S, snippet] both report {0,1} as competitive or better.

## 2. ZERO-COST methods ranked for our measurements

Our measurements:
- (M1) The binary model underfits: train 76 vs 91.
- (M2) The loss is spread across all 16 BinActs: each 1-bit view loses 0.2–4.4 probe points, and conv relative error is 0.3–0.5.
- (M3) Gradient flow is healthy. The clip-STE needs ×0.6, and ×0.8/1.0 collapses.
- (M4) QC sparsity: 25–319 distinct integer values per conv.
- (M5) Already tried: FP init, logit KD (TKD 58.54@ep85 screen), block-feature MSE KD (FKD 56.42, worse), clip/approx/bussgang/stein estimators, Bi-Real wiring, stage ablations.
- Our `qc18b/final.sh` sets `--qwd 0.1`, i.e. AdamW decoupled WD 0.1 on θ. Whether the binary runs used it is not checked here. Thresholds are in the SGD "other" group with no WD.

| Rank | Method | Mechanism to port | Targets | Reported gain |
|---|---|---|---|---|
| 1 | **Real-to-Binary progressive TS + attention matching** [3] | (a) Intermediate student with tanh soft-binarized activations, trained against the FP model, then used as teacher and init for the hard-binary student. (b) At block outputs 2–9: loss on max-normalized spatial attention mean_c(A²), weight 30. (c) Logit KL, weight 3, alongside CE. (d) Adam lr 1e-3, WD 1e-5, mixup, 350 ep on C100 | M1 (C100 train fit), M2 (supervision at every block, so no single-bottleneck assumption). Differs from our failed FKD: attention maps pool over channels, a far weaker constraint than per-channel MSE | **C100 R18, binary-act/real-W stage: Strong Baseline 69.3 → +AttTrans 72.2 → +AT+HKD 73.1 → +progressive TS 73.8 (+4.5); FP 78.3** [V Tab.3] |
| 2 | **AdamBNN / ReActNet training recipe** [5][4] | Zero WD on latents in the binarize-everything step (step 1 5e-6, step 2 0). Coupled-L2 Adam on conv weights only, 0 on BN, bias and threshold. KL-to-teacher **replacing** CE. Linear LR decay. Binarize activations before weights | M1. Directly challenges our θ AdamW WD 0.1: WD on latents raises flip-flop instability, while zero WD gives more fitting. Also bears on M3: Adam lowers activation saturation | ImageNet: WD/two-step 61.49→63.23 (+1.7). KL loss +1.4. BABW vs BWBA +3.1 [all V] |
| 3 | **Activation distribution loss** (Ding) [13] | Per BinAct channel, on u = x − t_c over (N,H,W), μ and σ: degeneration (μ²−σ²)₊; gradient mismatch [(2 − \|μ\| − σ)₊]²; saturation [(σ − 4)₊]². Those are the code constants for hardtanh window 1 and would need rescaling to our window w. Paper form: [(1−\|μ\|−kσ)₊]², k=0.25. λ=2, switched off after a set epoch | M1 (lowers train loss) and M3 / threshold-region mass. Keeps mass inside the STE window and stops channels going near-constant (our gradflow logs `const`, `pass`). Spread over all 16 sites (M2) | C100 ResNet-20-wide **+7.0 to +7.8** over a weak BNN baseline; train loss lower throughout [V] |
| 4 | **Progressive / stochastic binarization** (StoMPP [23]; R2B tanh step [3]) | Per step, a random mask chooses which elements or channels of each BinAct are hard. The rest stay a soft clip/tanh with true gradient. Hard fraction anneals 0→1 layer-wise | M2 (each of the 16 views degrades gradually; extends our `--fp-blocks` stage result 53.7–58.9 to the element level) | C100 R18 BNN +4.7 vs naive STE [V]; weak absolute baseline |
| 5 | SURGE dual-path gradient [24] | Training-only FP twin conv per QCConv on the un-binarized input. Forward exact, backward adds λ·∂f_fp/∂x with λ set by norm ratio | M2 in principle. M3 says gradients are already healthy, so low expected payoff | +0.6 C10 R20, +0.2 ImageNet vs RBONN [V]. No code |
| 6 | Estimator shape (ApproxSign, EDE, FDA, ReSTE, BiPer) [2][6][8][19][20] | – | M3: already covered by our clip/approx/bussgang/stein | ≤1–2 points ImageNet. Low |
| 7 | Threshold shift / {0,1} (Kim [12], Si-BNN [11]) | Fixed init shift; BN bias already learns the threshold | M5 (we learn t_c with SGD lr 0.1) | Small [S] |

Weight-side ZERO-cost methods (RBNN, ReCU, SiMaN, IR-Net Libra-PB, ReBNN/OvSW) are not ranked. Our weights are QC-structured, not sign(latent), and Schoenbauer [21] shows the weight-estimator shape is moot under Adam.

## 3. Methods claiming 1-bit-activation ResNet-18 on CIFAR-100

| Source | Setting | Top-1 |
|---|---|---|
| Real-to-Binary Tab.3 [V] | R18, A1 W-real (stage 1) / A1W1 (stage 2), binary downsample | SB 69.3/68.0; +ProgTS (ZERO-cost parts only) 73.8/72.3; full R2B (with gating, COST) 75.0/73.5; FP 78.3 |
| Real-to-Binary Tab.3 [V] | Same, real downsample (COST) | full R2B 76.5/76.2; FP+TS 79.3 |
| BNext-18 [V, parsed] | W1A1, COST architecture | ≈72.2 |
| NeuroBlend table [S] | Bi-Real-18 / ReActNet-18 | 63.51 / 70.76 |
| StoMPP [V] | R18 BNN, STE baseline vs StoMPP | relative +4.7 only |

Their FP R18 baseline is 78.3, ours is 68.6. Compare relative gaps: their Strong Baseline loses 9.0 points in the A1 stage, and ours loses 6.2.

## 4. Cloned repos (`/workspace/qc-nn/temp/`, gitignored, depth 1)

1. **`real2binary_larqzoo`**: larq/zoo, a TensorFlow re-implementation linked from the official `brais-martinez/real2binary` README. That repo contains only "code is still coming".
   - `larq_zoo/training/multi_stage_experiments.py`, `TrainR2B` and stages `TrainR2BBFP` / `TrainR2BBAN` / `TrainR2BBNN(Alternative)`:
     - Stage 0: FP R18.
     - Stage 1: FP student whose `input_quantizer` = tanh (`literature/real_to_bin_nets.py: RealToBinNetFPFactory`).
     - Stage 2: binary activations, teacher = stage 1.
     - Stage 3: all binary, teacher = stage 2, init from stage 2.
     - Loss weights: CE 1, attention 30 on `block_{2..9}_out`, KL 3 (KL 0.8 and no attention in stage 3). Adam lr 1e-3, 1e-3, then 2e-4.
   - `larq_zoo/training/knowledge_distillation/knowledge_distillation.py: AttentionMatchingLossLayer._normalized_attention_vector / _layer_attention_loss`. It computes q = mean_c(A²) per spatial position, flattens, divides by its max, and takes the mean squared error between student and teacher q. `OutputDistributionMatchingLossLayer.call`: T²·KL(softmax(t/T) ‖ softmax(s/T)).
2. **`ReActNet`** (official, liuzechun):
   - `utils/KD_loss.py: DistributionLoss.forward` returns −Σ softmax(teacher)·log_softmax(student). This is the soft-target cross-entropy and is the **only** loss (no CE).
   - `resnet/1_step1/birealnet.py`: real weights with `BinaryActivation` + `LearnableBias` (RSign).
   - `resnet/2_step2/birealnet.py`: swaps in `HardBinaryConv` and loads `checkpoint_ba.pth.tar`.
   - `BinaryActivation.forward`: forward sign. Backward through the piecewise quadratic (x²+2x | −x²+2x on [−1,1]), i.e. ApproxSign.
3. **`AdamBNN`** (official, liuzechun):
   - `step1/train.py` lines 77–91: Adam with two parameter groups, conv/4-D weights at `weight_decay=args.weight_decay` and everything else (BN, biases, RPReLU) at 0. Linear LR decay to 0 (`LambdaLR(1−step/epochs)`).
   - `step1/run.sh` uses WD 5e-6; `step2/run.sh` uses WD 0 and initializes from step 1. lr 1.25e-3, 256 epochs, KL to a ResNet-34 teacher.
4. **`DistributionLoss`**: `waterbearbee/DistributionLoss`, a mirror of the paper code. The official `enyac-group/DistributionLoss` is README-only and points to a deleted repo, so this mirror is not verified official.
   - `models/distrloss_layer.py: Distrloss_layer.forward` takes per-channel μ and σ over (N,H,W) of the pre-binarization input and returns two terms:
     - loss1 = mean[(min(2−μ−σ, 2+μ−σ))₊²] + mean[(σ−4)₊²], covering gradient mismatch and saturation.
     - loss2 = mean[(μ²−σ²)₊], covering degeneration.
   - `custom_main_binary_imagenet.py` lines 218–224: total = CE + λ(loss1+loss2), applied only while epoch < `distr_epoch`. It is attached after each BN before each hardtanh/sign in `models/alexnet_binary_vs_xnor.py`.

## References

1. Rastegari et al., XNOR-Net, ECCV 2016. https://arxiv.org/abs/1603.05279
2. Liu et al., Bi-Real Net, ECCV 2018. https://arxiv.org/abs/1808.00278
3. Martinez, Yang, Bulat, Tzimiropoulos, Real-to-Binary Convolutions, ICLR 2020. https://arxiv.org/abs/2003.11535. Code: https://github.com/larq/zoo
4. Liu et al., ReActNet, ECCV 2020. https://arxiv.org/abs/2003.03488. https://github.com/liuzechun/ReActNet
5. Liu et al., How Do Adam and Training Strategies Help BNNs Optimization?, ICML 2021. https://arxiv.org/abs/2106.11309. https://github.com/liuzechun/AdamBNN
6. Qin et al., IR-Net, CVPR 2020. https://arxiv.org/abs/1909.10788
7. Lin et al., Rotated BNN, NeurIPS 2020. https://arxiv.org/abs/2009.13055
8. Xu et al., FDA-BNN, NeurIPS 2021. https://arxiv.org/abs/2103.00841
9. Xu et al., ReCU, ICCV 2021. https://arxiv.org/abs/2103.12369
10. Lin et al., SiMaN, TPAMI. https://arxiv.org/abs/2102.07981
11. Wang et al., Sparsity-Inducing BNNs (Si-BNN), AAAI 2020. https://cdn.aaai.org/ojs/6900/6900-13-10129-1-10-20200525.pdf
12. Kim et al., Unbalanced Activation Distribution, WACV 2021. https://arxiv.org/abs/2012.00938
13. Ding et al., Regularizing Activation Distribution, CVPR 2019. https://arxiv.org/abs/1904.02823. Code mirror: https://github.com/waterbearbee/DistributionLoss
14. Tu et al., AdaBin, ECCV 2022. https://arxiv.org/abs/2208.08084
15. Bethge et al., MeliusNet, 2020. https://arxiv.org/abs/2001.05936
16. Lee et al., INSTA-BNN, ICCV 2023. https://arxiv.org/abs/2204.07439
17. Zhang, Zhang, Lew, PokeBNN, CVPR 2022. https://arxiv.org/abs/2112.00133
18. Guo et al., BNext, arXiv 2022 / TMLR 2023. https://arxiv.org/abs/2211.12933
19. Wu et al., ReSTE, ICCV 2023. https://arxiv.org/abs/2308.06689
20. Vargas et al., BiPer, CVPR 2024. https://arxiv.org/abs/2404.01278. https://github.com/edmav4/biper
21. Schoenbauer et al., Custom Gradient Estimators are STEs in Disguise, arXiv 2024. https://arxiv.org/abs/2405.05171
22. Chen et al., Hyperbolic BNN, TNNLS 2025. https://arxiv.org/abs/2501.03471
23. Smith & Islam, StoMPP: Layerwise Progressive Freezing, arXiv Jan 2026. https://arxiv.org/abs/2601.22660
24. Huang et al., SURGE, ICML 2026. https://arxiv.org/abs/2605.10989
25. Liu et al., Circulant Binary Convolutional Networks, CVPR 2019. https://arxiv.org/abs/1910.10853
26. Wang et al., Sub-bit Neural Networks, ICCV 2021. https://arxiv.org/abs/2110.09195
27. Salishev et al., GDNSQ, arXiv 2025. https://arxiv.org/abs/2508.14004
28. Bethge et al., Back to Simplicity, 2019. https://arxiv.org/abs/1906.08637
29. Xing et al., Modeling Contextual Dependencies (BCDNet), ECCV 2022. https://arxiv.org/abs/2209.01404
30. NeuroBlend (source of the Bi-Real-18 / ReActNet-18 C100 numbers) [S]. https://arxiv.org/abs/2307.03784
