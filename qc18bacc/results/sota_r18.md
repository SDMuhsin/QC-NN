# qc18bacc: ResNet-18 competitive set 2021-2026

Compiled 2026-11-15 by a literature sub-agent. Not committed.

This file extends [`../../llmdocs/sota_resnet18.md`](../../llmdocs/sota_resnet18.md) (CIFAR-10, energy-focused) and [`../../qc18acc/results/sota.md`](../../qc18acc/results/sota.md). It does not repeat their entries, except:

- ChewBaccaNN, which is copied from them;
- Valavi, which is now **re-read in the primary JSSC'19 PDF**.

Paper PDFs and text dumps are in the session scratchpad (`.../scratchpad/lit/<paper>/`), not in the repo.

## Tags and conventions

**Tags.** These are the same as the earlier files.

- **[V]** I read the number in the primary source text or table: pdftotext of an arXiv, author, NSF-PAR or thesis PDF, or open-access journal HTML.
- **[A]** The number comes from the abstract only (IEEE abstract text via Semantic Scholar, or from the title).
- **[S: x]** The number comes from secondary source x, which I read myself. x is named in each case.
- **[D]** I derived the number. The arithmetic is shown.
- Blank or "nr" means not found. Nothing is guessed.

**Our reference point (qc18bacc).** These numbers are as given in the brief; they are not re-measured here.

- TSMC 65 nm, about 20-24 mm² die, all weights on-chip.
- 73,728 MAC slots per cycle, about 490 MHz.
- Executed TOPS/mm²: peak about 3.0-3.6, workload average about 1.3-1.5. About 10 TOPS/W.
- ops = 2 × executed nonzero-ternary MACs. Each ternary × {1 b, int8} MAC counts as 2 ops.

Derived from these numbers:

- **Peak slots:** 73,728 × 2 × 490 MHz = 72.3 TOPS. Over 24 mm² that is 3.01, and over 20 mm² it is 3.61 TOPS/mm² [D]. This matches the brief.
- **Workload:** 119.87 M executed MAC per image = **239.7 Mop/image** ([M], E6_s0, `qc18bacc/workload.py`, project log).
- **Throughput:** average TOPS = 1.3-1.5 × 20-24 mm² = 26-36 TOPS. That gives **108 k-150 k images/s** [D].
- **Energy:** 239.7 Mop / 10 TOPS/W = **24 µJ/inference** [D].

**Network:** CIFAR-100 ResNet-18 with 1-bit activations. **Accuracy (PI correction):** hardware golden IntBin2 val (5 000 images) 64.04 / 63.90 % s0/s1 [M] (`results/golden_p2.md`); the qc18b model release measured the test set once: E6 float 63.33 / 63.64 %, IntBin 63.22 / 63.44 % [M] (`qc18b/RESULTS.md`); IntBin2 test not yet run (reserved for the end).

**Op conventions.** Every TOPS figure carries its paper's own op convention, which is stated per entry. The derived "executed" column uses one convention throughout:

- 1 op per MAC-half (a MAC is 2 ops), whatever the bit width.
- No 1-b normalisation.
- No dense-equivalent credit for skipped zeros.

Where a paper reports 1-b-normalised ops (ops × W_b × A_b) or includes skipped ops, I convert back only where the bit widths or the MAC count are given.

**Node normalisation to 65 nm. This is rough; use it as an order-of-magnitude guide only.**

- **Area:** TOPS/mm²₆₅ = TOPS/mm² × (L/65)². Frequency is *not* scaled. That favours newer-node competitors; scaling delay by L/65 as well would give (L/65)³.
  - Factors: 28 nm 0.186; 22 nm 0.115; 16 nm 0.061; 12 nm 0.034; 40 nm 0.379.
  - Stillmaker Table 4 gives similar values (28≈32 nm: 1/3.3 = 0.30; 22≈20 nm: 1/7.1 = 0.14), already quoted in `llmdocs/sota_resnet18.md`.
- **Energy:** classical E ∝ C·V² with C ∝ L, so TOPS/W₆₅ at 1.0 V = TOPS/W × (L/65) × (V/1.0 V)², using V as reported.
  - When V is not reported, I give only the iso-V L-factor. That is the minimum penalty.
  - The Stillmaker factors in `llmdocs/sota_resnet18.md` are 1.5-3× harsher on 22-28 nm low-V points.
  - Analog/CIM energy does not scale like logic. This is even rougher.

**External constant.** Torchvision ResNet-18 (ImageNet, 224²) = 1.81 GMAC = 3.62 GOP [S: torchvision model documentation, "1.81 GFLOPS" = MACs]. I use it only where a paper gives fps but no op count. Each such use is flagged.

---

## Table 1: Identity, implementation, memory

| # | Design (venue, year, first author) | Si / PL / Sim | Node | Area (mm²) | Weights resident on-chip for ResNet-18? | f, V at reported point | W / A precision |
|---|---|---|---|---|---|---|---|
| B | **Valavi**, JSSC'19 (baseline, pre-window) | Si [V] | 65 nm [V] | 12.6 [D: 18,876 GOPS / 1,498 GOPS/mm² = 12.60] | 2.4 Mb; ran VGG-style BNNs, not ResNet-18 [V] | 100 MHz, 1.2 V nominal; the 866 TOPS/W point is at 0.68 / 0.94 V [V] | 1 b / 1 b [V] |
| 1 | **PIMCA**, VLSI'21 + JSSC'23, B. Zhang (ASU/Seo) | Si [V] | 28 nm [V] | 20.9 die (5.90 × 3.54) [V] | **No.** "ResNet-18 needs time-multiplexing use of IMC macros, and its energy is evaluated on the 6th basic block (off-chip DRAM power/latency not included)" [V] | 40 MHz, 1.0 V [V] (JSSC: 42 MHz, 1 V [A]) | 1-2 b / 1-2 b [V] |
| 2 | **Neuro-CIM**, VLSI'22 (JSSC'23), Sangyeob Kim (KAIST) | Si [V: HC34 slides] | 28 nm [V] | 2.91 die [D: 3,228 µm × 900 µm] | **No.** 32 KB CIM storage [V] vs 11 M weights | 200 MHz, 1.1 V [V] | W 1/4/8 b, I 4 b, spiking [V] |
| 3 | **1T1C-eDRAM SNN-CIM**, JSTS 25(4) 2025, Sangmyoung Lee (KAIST) | Si: "fabricated using 28 nm", Fig. 9 "chip photo" [V] | 28 nm [V] | 10.47 [V] | Reports both "excl. EMA" and "incl. EMA", so not resident [V]. 19 Mb memory [V] | 250 MHz [V], V nr | 1 b W (4 b extension), spike-train A [V] |
| 4 | **CHIMERA**, VLSI'21 + JSSC'22, K. Prabhu / M. Giordano (Stanford) | Si [A] | 40 nm [A] | nr | "no off-chip memory", 2 MB RRAM [A]; scales to 6× larger DNNs over 6 chips [A] | nr | nr |
| 5 | **DIANA**, ISSCC'22 + JSSC'23, P. Houshmand (KU Leuven) | Si [A] | 22 nm FDX [A] | 10.24 die [S: Marsellus Table II] (8.91 [S: EE Times, prior file]) | AIMC 500 k cells, ternary, plus 256 kB L1 [V: ODiMO]. ResNet-18 CIFAR-100 run end-to-end on chip [V: ODiMO] | 260 MHz for the ResNet-18 runs [V: ODiMO] | AIMC: I/W/O 7/1.5/6 b (ternary W); digital 8/8/8 [A] |
| 6 | **Marsellus**, JSSC'24, F. Conti (ETH/Bologna) | Si [V] | 22 nm FDX [V] | 18.7 die (cluster 2.42) [V] | No. 1 MiB L2 [V] vs 11.7 M × 4 b = 5.8 MB [D] | Peak 0.8 V + ABB; efficiency point 0.5 V [V] | RBE 2-8 b; ResNet-18 at 4 × 4 b [V] |
| 7 | **QNAP**, ISSCC'21 + JSSC'22, H. Mo (Tsinghua) | Si [A] | 28 nm [A] | 1.9 core [A] | nr (206 KiB SRAM [S: Marsellus T.II]), so no | 470 MHz, 0.9 V [A] | 8 b, effective-weight / zero-skip [A] |
| 8 | **Bootstrapped-SRAM CIM**, TCAS-I'24, W. Mao (PolyU/SUSTech) | Si: "die photograph", "by measurements" [V: thesis] | 28 nm [V] | 2.59 [V: thesis Table] | **No.** 1152×128 array (0.14 Mb) [V] | 160-340 MHz, 0.9-0.95 V [V] | A/W 2/4/8 b, layer-wise mixed + bit sparsity [V] |
| 9 | **STICKER-IM**, JSSC'22, J. Yue (Tsinghua) | Si [A] | **65 nm** [A] | 5.66 [S: Mao thesis Table; PIMCA Table I lists 5.66 for the ISSCC'20 version] | nr; CIM capacity small, so no | 25-100 MHz [S: Mao] / 50-100 [S: CADC]; 0.9-1.05 V [S] | A 4-8 b, W 4/8 b [S] |
| 10 | **SparseCol**, arXiv 2606.16016 (2026), Man Shi (KU Leuven/Verhelst) | Si (taped out, measured) [V] | 16 nm [V] | 6.5 die / 4.61 core [V] | **No.** 2.5 MB on-chip; ResNet-18 inf/s "excluding off-chip memory" [V] | 280 MHz @ 0.93 V (perf.); 71.4 MHz @ 0.6 V (eff.) [V] | 8 b × 8 b, structured bit-column sparsity [V] |
| 11 | **SC-SRAM IMC macro**, ESSERC'24, J. Lee / B. Zhang / N. Verma | Si, macro only [A] | 28 nm [A] | nr (1152 × 256 array) [A] | macro; ResNet-18 "mapped" [A] | nr | multi-bit (nr) [A] |
| 12 | **ChewBaccaNN**, ISCAS'21, R. Andri (ETH) (copied from prior file) | Post-layout [V-prior] | 22 nm FDX | 0.7 | No; weights streamed [V-prior] | 154 MHz, 0.4 V | 1 b / 1 b |
| 13 | **Mixed analog-digital CIM**, JSTS 25(4) 2025, Byeongcheol Kim (KAIST) | Layout + corner simulation. "Layout photograph"; accuracy given at SS/FF corners. Silicon not claimed [V] | 28 nm [V] | 1.96 (1.4 × 1.4) [V] | No; 36 KB macro [V] | 200 MHz, 1.0 V core / 0.7 V peri [V] | W 6 b, A 4/8 b mixed (3-5 % outliers) [V] |
| 14 | **GAVINA**, ISLPED'25, arXiv 2511.23203 | Post-layout [V] | 12 nm [V] | 3.36 (1.6 × 2.1) [V] | No; 74 kB × 2 [V] | 50 MHz; 0.55 / 0.35 V guarded/approx [V] | a2w2 … a8w8 bit-serial [V] |
| 15 | **CADC**, arXiv 2511.22166 (2025) | Sim: SPICE crossbar + NeuroSim system + 65 nm synthesis [V] | **65 nm** [V] | macro core 0.5 [V]; system nr | NeuroSim system; nr | 200 MHz, 1.1 V [V] | I/W/O 4/2/4 b [V] |
| 16 | **PACiM**, ICCAD'24, W. Zhang (Keio) | Post-layout CnM unit + D-CiM bank *scaled from TSMC ISSCC'21* [V] | **65 nm** [V] | nr | nr | 100 MHz, 1.2 V (breakdown); 0.6 V for 14.63 TOPS/W [V] | 8b/8b with 4-b PAC approximation [V] |
| 17 | **OSA-HCIM**, ASP-DAC'24, Y.-C. Chen (Keio) | Sim (64b × 144b macro layout) [V] | **65 nm** [V] | nr | macro | nr | hybrid digital/analog, dynamic precision [V] |

## Table 2: Performance as reported, plus ResNet-18 workload

| # | Peak TOPS (own convention) | Peak TOPS/mm² (own) | Peak TOPS/W (own) | Op convention | ResNet-18 dataset, accuracy | ResNet-18 measured throughput / energy |
|---|---|---|---|---|---|---|
| B Valavi | 18.876 (HL conv); 9.438 with BN [V] | **1.498 / 0.749** [V] | 866 HL; 658 with BN [V] | 1b × 1b MAC = 2 ops. Throughput is *estimated* from cycle counts with no pipelining, and demo throughput was limited by the FPGA [V] | none (VGG BNNs on MNIST/CIFAR-10/SVHN) | — |
| 1 PIMCA | **4.9 (1b)** at 40 MHz [V, VLSI'21 text and Table]; **49 at 42 MHz** [A, JSSC'23]. See note 1 | 0.234 [D: 4.9/20.9] or **2.34** [D: 49/20.9] | macro 588; system 437 (1b) [V] | binary ops ("1b"); 2b mode reported separately | CIFAR-10 [A]; accuracy nr | **ResNet-18 avg system 136 TOPS/W (1b/1b), 35 (2b/2b)**, 6th basic block only, DRAM excluded [V]. fps nr |
| 2 Neuro-CIM | nr | nr | 310.4 (I4/W1), 124.2 (I4/W4), 62.1 (I4/W8) system [V], measured on "CIFAR-10 with ResNet-18" [V]; 1034.6 "bank" [V] | not stated | CIFAR-10 [V]; SNN conversion. Accuracy on the slides is for other networks | system power 105.4-241.4 mW [V]; fps nr |
| 3 SNN-eDRAM | nr | nr | macro 382-1531.3 [V] | not defined [V] | CIFAR-10 **94.13 %** (CNN→SNN) [V] | **157.15 TOPS/W excl. EMA → 0.03 TOPS/W incl. EMA** (CIFAR-10); ImageNet ResNet-18 86.63 → 0.53 [V]. Power 96 mW [V]. fps nr |
| 4 CHIMERA | 0.92 [A] | nr | 2.2 [A] | nr | ImageNet (acc. nr) | **8.1 mJ/image, 60 ms/image, 136 mW, 2.2 TOPS/W** [S: SemiWiki write-up, via search-engine excerpt; page blocked to direct fetch] → 16.7 fps [D] |
| 5 DIANA | AIMC 29.5; digital 0.18 [S: Marsellus T.II] | AIMC **2.9**; digital 0.0176 [S: Marsellus T.II]; 29.5/10.24 = 2.88 die-level [D] | AIMC 600 (7/1.5/6 b); digital 14 [A] | MAC = 2 ops at stated precision; ternary zeros counted (dense) | **CIFAR-100: 74.10 % (all-8b), 72.74 / 71.82 % (ODiMO), 70.86 % (min-cost, 96 % channels on AIMC)** [V: ODiMO]. ImageNet 69.33 → 58.38 % [V] | **CIFAR-100 measured @260 MHz: 30.3 ms / 756 µJ (all-8b); 2.14 ms / 65.9 µJ (ODiMO-Fast); 1.62 ms / 47.6 µJ (min-cost)** [V: ODiMO]. ImageNet 63.2 ms / 1578 µJ → 4.25 ms / 129 µJ [V]. ResNet-18 ImageNet 19 TOPS/W, 6.15 ms [S: Marsellus T.II]. System 7.02 (CIFAR-10) / 5.56 (ImageNet) [A] |
| 6 Marsellus | RBE 0.637 (2×2b, 0.8 V + ABB) [V] | 0.0341 [V] | 12.4 (2×2b, 0.5 V) [V] | ops at the layer precision | ImageNet, HAWQ 4b, 68.5 % [V] | **ResNet-18/ImageNet: 5.83 TOPS/W (RBE 4×4b), 48 ms** [V] → 20.8 fps [D] |
| 7 QNAP | 0.140 (8b) [S: Marsellus T.II] | 0.0737 [S] | 12.6 @ 140 GOPS (8b) [S] | 8b ops; zero-skipping credit unclear | ImageNet (acc. nr) | **ResNet-18/ImageNet 12.1 TOPS/W (zero-skipping), 24.8 ms** [S: Marsellus T.II] → 40.3 fps [D]; ImageNet mix average 117.4 fps, 131.6 mW [A] |
| 8 Mao CIM | nr | nr | 302.78 (2b), 75.69 (4b), 18.91 (8b) [V] | at stated precision (not 1b-normalised); bit-sparsity exploited | CIFAR-10 ResNet-18: 91.29 % (4b mixed), 90.55 % (2b mixed), 92.42 % (8/8 fixed) [V: thesis Table 6.1] | **ResNet-18 average 135.19 TOPS/W (mixed)** [V]; fps nr |
| 9 STICKER-IM | 0.17-2.0 (ISSCC'20 version) [S: PIMCA T.I]; 0.20 on ResNet-18 [S: CADC T.II] | 0.35 [D: 2.0/5.66] (own, low-precision) | macro 158.7, system 35.8 (ISSCC'20) [S: PIMCA T.I]; avg system 5.8-158 on sparse NNs [A] | sparsity-aware; probably dense-equivalent (not verifiable) | CIFAR-10, accuracy loss 0.52 % [S: CADC] | **ResNet-18: 6.91 TOPS/W (4b) / 1.78 (8b)** [S: Mao thesis; CADC (normalised to 65 nm / 1.1 V; same node)]; 0.20 TOPS [S: CADC] |
| 10 SparseCol | 54.72 BTOPS @ 0.93 V [V] | 8.41 BTOPS/mm² [V] | 1320.8 S-BTOPS/W @ 0.6 V (6 zero columns) [V] | **BTOPS = W_b × A_b × TOPS, including skipped sparse ops** [V] | ImageNet 69.12 % (INT8 baseline 69.35) [V] | **27.8-105.4 inf/s (excl. off-chip); 254.4 S-BTOPS/W @ 0.93 V, 738.6 @ 0.6 V** [V] |
| 11 Lee/Verma macro | nr | **111.8 (1b-normalised)** [A] | **8161 (1b-normalised)** [A] | 1b-normalised | ResNet-18 *mapped*: CIFAR-10 92.34 %, ImageNet 69.88 % [A] | — (macro) |
| 12 ChewBaccaNN | nr | nr | 223 peak core [V-prior] | binary ops | binary ResNet-18 CIFAR-10 91.5 % [V-prior] | 324.3 fps, 21.8 GOPS, 7.3 µJ incl. I/O [V-prior]. Net size given as 175 MOp, *not* the 1.11 GOp kuangliu net: check before use |
| 13 Kim JSTS | 0.3985 peak [V] | 0.203 [D: 0.3985/1.96] | 85.7 (CIFAR-100) [V] | Table footnote: "normalized per macro, scaled with bits" [V] | **CIFAR-100: 77.1 % (A4) / 77.4 % (A8 outliers)** [V] | power 27.56 mW [V]; fps nr |
| 14 GAVINA | 1.774 (a2w2), 0.111 (a8w8) [V] | 0.528 (a2w2) [D: 1.774/3.36] | 45.87-89.32 (a2w2, scaled to 12 nm) [V] | MAC = 2 ops at stated precision | CIFAR-10 (undervolting study) [V] | nr |
| 15 CADC | 2.15 on ResNet-18 [V] | nr | 40.8 on ResNet-18 [V] | 4/2/4 b | CIFAR-10, accuracy loss 0.35 % [V] | 2.15 TOPS, 40.8 TOPS/W (system, NeuroSim) [V] |
| 16 PACiM | nr | nr | 14.63 (8b/8b) = 1170.28 1b-normalised [V] | both given | **CIFAR-100 72.36 %**, CIFAR-10 93.85 %, ImageNet 66.02 % (sim.) [V] | nr |
| 17 OSA-HCIM | nr | nr | 5.33-5.79 [V] | nr | CIFAR-100 (accuracy only in a plot) [V] | nr |

## Table 3: Normalised to 65 nm, and executed ops

Rules are given in the header. All values are [D]. Arithmetic: "×0.186" means × (28/65)²; the energy factor is (L/65)·V².

| # | Peak TOPS/mm² at 65 nm (area-only scaling) | Executed-op note (1 op per MAC-half, no bit normalisation, no skipped-op credit) | TOPS/W at 65 nm / 1.0 V |
|---|---|---|---|
| B Valavi | **1.498** (native, 65 nm) | 1b MAC = 2 ops, every slot. Same as our convention for a binary MAC | 866 at 0.68/0.94 V; not comparable at 1.0 V |
| 1 PIMCA | 4.9-TOPS reading: 0.234 × 0.186 = **0.044**. 49-TOPS reading: 2.34 × 0.186 = **0.435** | 1b/1b binary MAC = 2 ops. Same as our convention | system peak 437 × 28/65 = 188; **ResNet-18 136 × 28/65 = 58.6** (2b: 15.1). Excludes DRAM |
| 2 Neuro-CIM | nr | nr | 310.4 × (28/65) × 1.1² = **162** (I4/W1); 64.7 (W4); 32.4 (W8). Weights off-chip; EMA treatment not stated on the slides |
| 3 SNN-eDRAM | nr | nr | excl. EMA 157.15 × 28/65 = 67.7 (iso-V); **incl. EMA 0.03 × 28/65 = 0.013** |
| 4 CHIMERA | nr | nr | 2.2 × 40/65 = 1.35 (iso-V; V nr) |
| 5 DIANA | AIMC 2.9 × 0.115 = **0.33**; digital 0.0176 × 0.115 = 0.002 | AIMC counts ternary-zero weights (dense), so executed ≤ reported. CIFAR-100 ResNet-18 end-to-end: if the net is kuangliu-size (0.556 GMAC, *assumption*), 1.112 GOP / 1.62 ms = 0.69 TOPS, i.e. **0.067 TOPS/mm²** (die, 22 nm) | ResNet-18 ImageNet 19 × 22/65 = 6.4 (iso-V); µJ at iso-V: 47.6 × 2.95 = 141; 65.9 → 195; 756 → 2,234 µJ |
| 6 Marsellus | 0.0341 × 0.115 = **0.0039** | 2×2b MACs, dense | 12.4 × (22/65) × 0.5² = 1.05; ResNet-18 5.83 × 22/65 = 1.97 (iso-V) |
| 7 QNAP | 0.0737 × 0.186 = **0.0137** | 8b MACs; ResNet-18 12.1 TOPS/W includes zero-skip credit (unverified) | 12.1 × (28/65) × 0.9² = 4.2 |
| 8 Mao CIM | nr | at stated precision; bit-sparsity credit unclear | 135.19 × (28/65) × 0.9² = **47.2** (0.95 V: 52.6); 2b peak 302.78 → 105.6 |
| 9 STICKER-IM | **0.35 native** (2.0/5.66, low precision); ResNet-18 0.20/5.66 = **0.035** | dense-equivalent likely; not verifiable | ResNet-18 6.91 (4b) / 1.78 (8b), already at 65 nm / 1.1 V; × (1.0/1.1)² = 5.7 / 1.5 at 1.0 V |
| 10 SparseCol | executed slots: 512 × 2 × 280 MHz = 0.287 TOPS; /6.5 = 0.044; × 0.061 = **0.0027**. BTOPS reading: 8.41/64 = 0.131 (8b, incl. skipped) × 0.061 = 0.008 | ResNet-18: 105.4 inf/s × 3.62 GOP (*torchvision constant*) = 0.38 TOPS dense-eq, /6.5 = 0.059 TOPS/mm² (16 nm) | 254.4/64 = 3.98 (8b dense-eq) × (16/65) × 0.93² = 0.85; 738.6/64 = 11.5 × (16/65) × 0.6² = 1.02 |
| 11 Lee/Verma | 1b-norm 111.8 × 0.186 = 20.7 (1b-norm). Not convertible: bit widths not in the abstract | — | 8161 1b-norm; not convertible |
| 12 ChewBaccaNN | ResNet-18 avg 21.8/0.7 = 31.1 GOPS/mm² × 0.115 = **0.0036** | binary op = 2 per MAC | (prior file: 7.3 µJ → 135-260 µJ at 65 nm) |
| 13 Kim JSTS | 0.203 × 0.186 = **0.038** | "scaled with bits": executed value nr | 85.7 × 28/65 × 1.0² = 36.9 |
| 14 GAVINA | 0.528 × 0.034 = **0.018** (a2w2) | 2b MACs, dense | given at 12 nm scale only |
| 15 CADC | nr (system area nr) | 4/2/4b | 40.8 (already 65 nm, 1.1 V) |
| 16 PACiM | nr | 8b/8b: 14.63 | 14.63 at 0.6 V, 65 nm → × 0.36 = 5.3 at 1.0 V |
| 17 OSA-HCIM | nr | — | 5.33-5.79 (65 nm) |
| **ours** | **3.0-3.6 peak; 1.3-1.5 avg (native 65 nm)** | executed nonzero-ternary MACs only | **~10** |

---

## Per-entry notes

**B. Valavi, JSSC'19 (baseline), re-read in the primary PDF.**

- The abstract gives HL/FL 866/1.25 TOPS/W and 18,876/43.2 GOPS (1,498/3.43 GOPS/mm²) for convolution, and 658/0.95 TOPS/W, 9,438 GOPS (749 GOPS/mm²) with batch-norm [V].
- Clock 100 MHz, nominal 1.2 V [V]. The 866 TOPS/W number is computed at the energy-optimal supplies, 0.68 V (broadcast/control) and 0.94 V (M-BC, BN) [V]. So the 1.5 TOPS/mm² and 866 TOPS/W figures are *different operating points*.
- Throughput is computed from 25 cycles per filter "assuming no pipelining". The paper notes that demonstration throughput is limited by the FPGA test setup, and that system throughput will depend on utilisation [V].
- So 1.498 GOPS/mm² is a convolution-only, layer-level peak, not an end-to-end figure.
- The PIMCA table also gives Valavi 0.94-1.2 V, 100 MHz, 18.9 TOPS, 866 peak / 658 avg [S: PIMCA Table I].

**1. PIMCA.** This is the closest *same-precision* (1b/1b ResNet-18) silicon competitor.

- Die 5.90 × 3.54 mm = 20.9 mm², 108 IMC macros of 256 × 128 10T1C cells (3.4 Mb), and 1.54 Mb activation SRAM [V].
- Throughput discrepancy:
  - The VLSI'21 text and table say "peak throughput is 4.9 TOPS (1-b)" at 40 MHz [V].
  - The JSSC'23 abstract says "peak throughput of 49 TOPS at the 42-MHz clock" [A].
  - Arithmetic check: one PE of 18 macros × 256 × 128 × 2 ops × 42 MHz = 49.5 TOPS [D]. Also 437 TOPS/W × 124 mW = 54 TOPS, whereas 4.9 TOPS / 124 mW = 39.5 TOPS/W [D].
  - So **49 TOPS is self-consistent with the reported power, and 4.9 is probably a typo**. Treat this as an inference; the JSSC full text is needed to confirm.
  - Under 49 TOPS, PIMCA is **2.34 TOPS/mm² at 28 nm**, which beats Valavi on raw area efficiency, and **0.44 at 65 nm** [D].
- ResNet-18 does not fit on-chip. Its energy is evaluated on one basic block, without DRAM [V].

**2. Neuro-CIM** (source: the HC34 slides by the first author).

- Die 3,228 × 900 µm, 28 nm, 1.1 V, 200 MHz, 32 KB digital SRAM [V].
- System efficiency 310.4/124.2/62.1 TOPS/W at I=4b with W=1/4/8 b. Footnote: "CIFAR-10 with ResNet-18 (64x160x16)" [V]. The meaning of "64x160x16" is not explained on the slide.
- No throughput is given. Weights cannot be resident.

**3. 1T1C-eDRAM SNN-CIM (KAIST, JSTS 2025).**

- This is the single most useful datum for the "weights on-chip" argument. The same chip and network (ResNet-18, CIFAR-10) give **157.15 TOPS/W excluding EMA but 0.03 TOPS/W including EMA**: a ~5,000× collapse [V].
- ImageNet ResNet-18: 86.63 → 0.53 [V]. That CIFAR falls further than ImageNet is as reported; it is not explained in the text I read.
- The full-text HTML is open access at jsts.org.

**4. CHIMERA.**

- The abstract confirms 40 nm, 0.92 TOPS, 2.2 TOPS/W, foundry RRAM, and "no off-chip memory" [A].
- The ResNet-18/ImageNet figures (8.1 mJ, 60 ms, 136 mW) come from a SemiWiki write-up as quoted by a search engine [S]. I could not open the page (bot wall), and I could not get the JSSC full text.
- 0.92 TOPS at 8.1 mJ/60 ms implies ResNet-18 runs at about 0.06 TOPS (3.62 GOP / 60 ms, *torchvision constant*), i.e. about 7 % of peak [D].
- 136 mW × 60 ms = 8.16 mJ, consistent with 8.1 mJ [D]. On ResNet-18 the efficiency is therefore 3.62 GOP / 8.1 mJ ≈ **0.45 TOPS/W** [D, torchvision constant], not 2.2. The 2.2 TOPS/W figure is the peak.
- Die area: not found.

**5. DIANA.** This is the best "same task" competitor: ternary weights, **CIFAR-100 ResNet-18, measured end-to-end on silicon**.

- The measurement is in ODiMO (Risso et al., IEEE TCAD 2025, arXiv 2409.18566, Table IV), which "replac[es] modeled latency and energy with measured values" at 260 MHz [V].
- Best accuracy/energy points: 74.10 % at 756 µJ / 30.3 ms (all-8b digital); 70.86 % at **47.6 µJ / 1.62 ms (617 fps)** [D for fps].
- The input size and exact ResNet-18 variant for CIFAR-100 are not given in the text I read. The op count is therefore unknown, and my 0.069 TOPS/mm² figure assumes the kuangliu size.
- Marsellus's Table II gives DIANA ResNet-18/ImageNet 19 TOPS/W and 6.15 ms, die 10.24 mm², and AIMC 2.9 TOPS/mm² [S].

**6. Marsellus.**

- ResNet-18/ImageNet (HAWQ 4-b, 68.5 %): 5.83 TOPS/W and 48 ms [V].
- Die 18.7 mm², cluster 2.42 mm² [V].
- Best accelerator area efficiency is 34.1 GOPS/mm² (2×2b) [V]. Marsellus states that QNAP is better on area efficiency [V].

**7. QNAP.**

- Abstract: 28 nm, 1.9 mm² core, 470 MHz, 0.9 V, 117.4 fps average over AlexNet/VGG/GoogLeNet/ResNet on ImageNet, 131.6 mW [A].
- The ResNet-18-specific 12.1 TOPS/W and 24.8 ms come from Marsellus's comparison table, footnoted "zero-skipping" [S].

**8. Mao et al., TCAS-I'24.**

- The figures are from the first author's PolyU thesis, Ch. 6: die photo, "measured" [V]. TCAS-I'24 is the venue as cited by CADC [S].
- Area 2.59 mm², 1152×128 9T1C array [V].
- ResNet-18 CIFAR-10 average 135.19 TOPS/W (mixed precision) and peak 302.78 TOPS/W at 2 b [V].
- The thesis abstract states "equivalent accuracy at 4-bit of 68.68 %". Table 6.1 instead gives 91.29 % for 4b-mixed ResNet-18 on CIFAR-10 [V]. These are inconsistent within the thesis. Use the table value, with caution.

**9. STICKER-IM** (65 nm, the same node as ours).

- The abstract confirms 65 nm silicon and 5.8-158 TOPS/W "average system energy efficiency on the sparse NN models" [A].
- ResNet-18/CIFAR-10 figures (6.91 TOPS/W at 4b, 1.78 at 8b; 0.20 TOPS; area 5.66 mm²) come from two independent secondary tables (Mao thesis, CADC) that agree [S].
- **ResNet-18 executes at about 0.035 TOPS/mm² at 65 nm** [D]. That is **~37-100× below our 1.3-3.6** [D: 1.3/0.035 = 37; 3.6/0.035 = 103].

**10. SparseCol.** This is the strongest *structured-sparse* silicon with a ResNet-18 measurement, and it is very recent (2026).

- Its efficiency figures count skipped operations and normalise by W_b × A_b (BTOPS) [V].
- Native executed peak is 0.044 TOPS/mm² at 16 nm [D].
- On ResNet-18/ImageNet it reaches 105.4 inf/s, excluding off-chip memory [V].
- Its comparison table also lists DA-SignM (ISSCC'23, 28 nm, 7.75 mm², 3.61 BTOPS/mm² at 0.9 V) [S: SparseCol Table IV]. A search snippet attributes ResNet-18 results to DA-SignM's journal version, but I could not open it (ACM bot wall). Not included.

**11. Lee/Zhang/Verma (ESSERC'24).** Macro-only, 1b-normalised: 8161 TOPS/W and 111.8 TOPS/mm². ResNet-18 is mapped for accuracy only [A]. This is the highest area-efficiency number in the set, but it is not a system and not comparable.

**12-17. Non-silicon entries.** These are included only because they report ResNet-18 at ≤ 4 b or at 65 nm. **None is a fair competitor for a silicon claim.**

- **GAVINA** has exactly our MAC count (73,728 = 576 × 8 × 16) but runs at 50 MHz in 12 nm: 0.53 TOPS/mm² at a2w2 [D].
- **Kim JSTS'25** is CIFAR-100 ResNet-18 at 77.4 % and 85.7 TOPS/W, but it is layout/corner-simulated.
- **PACiM** reports CIFAR-100 ResNet-18 72.36 % (simulated accuracy).

### Near-misses, not in the tables

These were checked and excluded because there is no ResNet-18, or ResNet-18 only as an accuracy side-note:

- IMPACT (ESSCIRC'22 / JSSC'23): MNIST only.
- IMAGINE (arXiv 2412.19750): CIFAR-10 at 8-1b, no ResNet-18.
- DynaPlasia (JSSC'24): ResNet-50, 20.25 mm², 19.5 TOPS, 29.5 TOPS/W [S: search snippet].
- Jia JSSC'22: ResNet-50.
- S2TA (HPCA'22): no ResNet-18.
- ASU FP8 sparse *training* processor (JSSC'23): ResNet-18 training.
- Z-PIM (65 nm, JSSC'21): VGG-16.
- Yoshioka 65 nm CR-CIM (ISSCC'24 / arXiv 2302.06463): macro; ResNet-18/20 accuracy only [S: PACiM Table 4].
- E-ReCON, Res-DPU, FERMI-ML, DS-CIM: 65/40 nm macro simulations.
- Yang JSSC'23 ternary charge-domain CNN (40 nm): 4-layer MNIST net.

---

## Where a 65 nm digital ternary / 1-bit design has a large margin, and where it clearly loses

This section uses only the tagged numbers above.

### Large-margin advantages

1. **Executed area efficiency at system level, same or normalised node.**
   - Our 3.0-3.6 peak and 1.3-1.5 average executed TOPS/mm² (65 nm, die, weights included) compare with:
     - Valavi 1.498 (conv-layer-only peak, no pipelining): 2.0-2.4× on peak [D];
     - PIMCA 0.44 at 65 nm, best case (49-TOPS reading) [D];
     - DIANA AIMC 0.33 at 65 nm [D];
     - STICKER-IM (same node) 0.35 peak and 0.035 on ResNet-18 [D];
     - every digital SoC (Marsellus 0.004, QNAP 0.014, SparseCol 0.003 at 65 nm) [D].
   - **Even without node scaling**, our peak is above PIMCA (2.34 at 28 nm, under the favourable 49-TOPS reading) and DIANA AIMC (2.9 at 22 nm). It is roughly 25-100× above the 16-28 nm digital SoCs' raw TOPS/mm² [D: 3.0-3.6 vs QNAP 0.074, Marsellus 0.034, SparseCol 0.044 executed or 0.13 incl. skipped].
   - The exception is macro-only CIM: Lee/Verma at 111.8 1b-normalised TOPS/mm². That is not a system figure.
2. **End-to-end ResNet-18 throughput.**
   - Ours: about 108-150 k images/s [D] on CIFAR-100.
   - Competitors' measured end-to-end ResNet-18 rates: DIANA CIFAR-100 33-617 fps [V/D]; ChewBaccaNN CIFAR-10 324 fps (post-layout) [V-prior]; SparseCol ImageNet ≤ 105 inf/s [V]; QNAP 40 fps, Marsellus 21 fps, CHIMERA 17 fps on ImageNet [S/D].
   - Even per mm² against DIANA on the same task: (~130 k / 22 mm²) / (617 / 10.24 mm²) ≈ 98× [D]. The DIANA numbers are at 22 nm and not scaled.
3. **Energy per inference with all weights resident.**
   - Ours: about 24 µJ/inference [D] on CIFAR-100 ResNet-18.
   - DIANA, the same task measured at 22 nm, needs 47.6-756 µJ [V] (≈141-2,234 µJ at 65 nm iso-V [D]).
   - Most high-TOPS/W CIM competitors **exclude DRAM while ResNet-18 does not fit on-chip**: PIMCA [V], Neuro-CIM, Mao, SNN-eDRAM. The KAIST SNN-eDRAM chip shows the cost directly: **157 → 0.03 TOPS/W when EMA is included** [V]. That is a strong, citable argument for all-on-chip weights.

### Clear losses

1. **Peak TOPS/W.**
   - Our ~10 TOPS/W loses to every ≤ 2-b CIM silicon point, even after node normalisation:
     - PIMCA ResNet-18 58.6 at 65 nm [D] (136 raw);
     - Neuro-CIM 162 [D];
     - Mao 47 [D];
     - SNN-eDRAM 68 (excluding EMA) [D];
     - Valavi 866 at 0.68/0.94 V [V].
   - We are about 5-16× worse on normalised TOPS/W [D: 47/10 to 162/10], counting their numbers with EMA excluded, as they report them.
   - We are roughly at parity or better against digital SoCs and multi-bit points: DIANA ResNet-18 6.4, QNAP 4.2, Marsellus 2.0, SparseCol ≈1, CHIMERA 1.35, STICKER-IM 1.5-5.7 [D].
2. **Accuracy on CIFAR-100 ResNet-18.**
   - Ours: ~63.3-63.6 % test (IntBin, qc18b/RESULTS.md) / 64.0 % val (IntBin2) [M].
   - DIANA on silicon: 70.86 % (min-cost) to 74.10 % [V].
   - Kim JSTS (simulated): 77.4 % [V].
   - PACiM (simulated): 72.36 % [V].
   - That is a **~7.4-point accuracy deficit against the only same-task silicon** [D: 70.86 - 63.5 = 7.4]. A reviewer will pair any throughput or µJ claim with this. The comparison must be iso-accuracy or must state the gap.
3. **Raw macro-level area efficiency.** Lee/Verma reach 111.8 1b-normalised TOPS/mm² [A]. TSMC-style digital CIM macros (not ResNet-18, not tabulated here) are in the same range. A macro-vs-macro comparison is lost; only the system-level, weights-included comparison is won.
4. **Node.** Every competitor except Valavi, STICKER-IM and the 65 nm simulation papers is at 12-40 nm. Without normalisation, our absolute TOPS/W and the competitors' µJ at 22 nm look closer than they are. With normalisation, the rules above are rough. Both views should be shown.

---

## Sources (read in this session)

- Valavi et al., JSSC 54(6) 2019. Primary PDF: princeton.edu/~nverma/VermaLabSite/Publications/2019/ValaviRamadgeNestlerVerma_JSSC2019.pdf
- B. Zhang et al., "PIMCA: A 3.4-Mb Programmable In-Memory Computing Accelerator in 28nm for On-Chip DNN Inference," VLSI 2021. PDF: par.nsf.gov/servlets/purl/10322663. JSSC 58(5) 2023, doi:10.1109/JSSC.2022.3211290 (abstract via Semantic Scholar).
- S. Kim et al., "Neuro-CIM: A 310.4 TOPS/W Neuromorphic CIM Processor…," VLSI 2022. Slides: hc34.hotchips.org/assets/program/posters/HC2022.KAIST.SangyeobKim.v1.pdf
- S. Lee et al., "A Reconfigurable SNN CIM Processor using 1T1C eDRAM…," JSTS 25(4):355-362, 2025 (jsts.org XmlViewer f438843).
- B. Kim et al., "An 85.7 TOPS/W Analog-digital Combined In-memory Computing Accelerator…," JSTS 25(4):346, 2025, doi:10.5573/JSTS.2025.25.4.346 (jsts.org XmlViewer f438842).
- K. Prabhu et al., "CHIMERA…," JSSC 57(4):1013-1026, 2022, doi:10.1109/JSSC.2022.3140753; VLSI 2021, doi:10.23919/VLSICircuits52068.2021.9492347 (abstracts via Semantic Scholar). SemiWiki ?p=314199 (search-engine excerpt only).
- P. Houshmand et al., "DIANA…," JSSC 58(1):203-215, 2023 (abstract). M. Risso, A. Burrello, D. Jahier Pagliari, "Optimizing DNN Inference on Multi-Accelerator SoCs at Training-time" (ODiMO), IEEE TCAD 2025, arXiv:2409.18566 (Table IV read).
- F. Conti et al., "Marsellus…," JSSC 59(1):128-142, 2024, arXiv:2305.08415 (Table II read).
- H. Mo et al., "A 12.1 TOPS/W Quantized Network Acceleration Processor…," JSSC 57(5):1542-1557, 2022 (abstract via Semantic Scholar).
- W. Mao et al., "A 28-nm 135.19 TOPS/W Bootstrapped-SRAM CIM Accelerator With Layer-Wise Precision and Sparsity," TCAS-I 2024. Author's thesis: theses.lib.polyu.edu.hk/bitstream/200/14152/3/8606.pdf (Ch. 6 read).
- J. Yue et al., "STICKER-IM…," JSSC 57(8):2560-2573, 2022 (abstract via Semantic Scholar).
- M. Shi et al., "SparseCol: A 1320 BTOPS/W Precision-scalable NPU…," arXiv:2606.16016 (2026).
- J. Lee, B. Zhang, N. Verma, ESSERC 2024, pp. 357-360 (abstract).
- R. Andri et al., ChewBaccaNN, ISCAS 2021 (values from `llmdocs/sota_resnet18.md`).
- GAVINA, ISLPED 2025, arXiv:2511.23203. CADC, arXiv:2511.22166. W. Zhang et al., PACiM, ICCAD 2024, arXiv:2408.16246. Y.-C. Chen et al., OSA-HCIM, ASP-DAC 2024, arXiv:2308.15040.
