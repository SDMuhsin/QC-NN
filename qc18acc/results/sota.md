# qc18acc vs state of the art

Status: draft. The routed v3 row is **provisional**: detailed route was stopped after iteration 4, with 70,584 DRC markers. It will be replaced when the route finishes (see `pnr_v3.md`).

## Conventions

**Workload (ours).** CIFAR-10 ResNet-18, kuangliu topology. Per inference that is 0.556 GMAC, i.e. **1.11 GOp at 2 op/MAC**.

**Our op counts are dense-equivalent.** We count the MACs a dense int8 network would execute. The PE actually performs ≤ 2 shifted ±1 terms per 8×8 block per output row, so the arithmetic done is about 1/5–1/8 of the dense-equivalent count. Equivalent-op metrics were criticised for CirCNN and PermDNN. Treat the TOPS and TOPS/W columns accordingly. The primary metrics are **µJ/inference and inferences/s/mm² at a stated accuracy**.

**Labels.**

| Label | Meaning |
|---|---|
| M | measured on our flow: RTL/GLS cycles, PrimeTime/PTPX with SAIF |
| S | synthesis-estimated: DC area with a wire-load model, pre-route |
| R | post-route, OpenROAD + SPEF |
| Mod | modelled |
| V | from the primary source text or table |
| A | from the abstract only |
| D | derived by us from tagged numbers |

**Normalisation to 65 nm, 1.0 V.**

- Energy uses two rules, and both are reported:
  - **Stillmaker & Baas** (Integration 58, 2017, Table 5). Bracket: 28 nm ≈ 32 nm HP, 22 nm ≈ 20 nm HP.
  - **Classical**, (65/L)·(1.0/V)².
- Area uses the Stillmaker Table 4 factor (×7.9 for 16 nm, ×7.1 for 20/22 nm, ×3.3 for 28/32 nm).
- Throughput is **not** normalised for speed. This favours newer-node competitors.

## Our design points (all: CIFAR-10 test 91.33 %, bit-exact RTL and GLS against `qc18/int8.py`)

| Point | Corner | f (MHz) | Cycles/img | img/s | Latency | Area (mm²) | Power (mW) | µJ/inf | TOPS (dense-eq) | TOPS/W (dense-eq) | TOPS/mm² |
|---|---|---|---|---|---|---|---|---|---|---|---|
| v2, pre-route | tt 1.0 V | 400 | 159,982 M | 2,500 | 400 µs | 6.430 S | 231.0 M/S | 92.4 | 2.78 | 12.0 | 0.43 |
| v2, routed (v2 recipe) | tt 1.0 V | 285.7 | 159,982 | 1,786 | 560 µs | 8.858 die R | 272.2 R | 152.4 | 1.98 | 7.3 | 0.22 |
| v2, routed (improved recipe) | tt 1.0 V | 285.7 | 159,982 | 1,786 | 560 µs | R | R | 141.2 | 1.98 | 7.9 | – |
| **v3, pre-route** | tt 1.0 V | 400 | 81,438 M | **4,912** | **204 µs** | 6.514 S | 336.2 M/S | **68.5** | **5.45** | **16.2** | **0.84** |
| v3, pre-route, low V | tt 0.8 V | 300 | 81,438 | 3,684 | 271 µs | 6.514 S | 156.5 Mod (macros V²) | **42.5** | 4.09 | 26.1 | 0.63 |
| v3, routed (**provisional**) | tt 1.0 V | 294 | 81,438 | 3,610 | 277 µs | 10.384 die R | 388.6 R | 107.6 | 4.01 | 10.3 | 0.39 |

Notes:

- All energy is on-chip. Weights and activations are fully resident, so there is no DRAM traffic per inference.
- The ablation (`ablation.md`) has a DRAM what-if.
- The 0.8 V macros are modelled, because the kit's memory compilers have no 0.8 V corner.

## Competitors

### Table A — Same or similar task, accuracy ≥ 91 % on CIFAR-10

| Design | Si? | Node, V | Network, precision, accuracy | Area (mm²) | img/s | Power | µJ/inf (reported) | µJ/inf at 65 nm, 1.0 V (Stillmaker / classical) |
|---|---|---|---|---|---|---|---|---|
| ChewBaccaNN [1] | post-layout | 22 nm FDX, 0.4 V | **ResNet-18**, binary (IR-Net), 91.5 % | 0.7 | 324 | 2.4 mW | 7.3 incl. I/O V | 260 / 135 (core only ≈ 100 / 52) D |
| Jia, 65 nm [2] | yes | 65 nm, 1.2 V or 0.85 V (unclear) | 11-layer CNN, 4b/4b, 92.4 % | 13.5 | 23 | ≈ 2.4 mW D | 105.2 V | 66 (if 1.2 V) – 147 (if 0.85 V) D |
| Jia, 16 nm [3] | yes | 16 nm, 0.8 V | 11-layer CNN, 4b/4b, 91.51 % | nr | **7,815** | ≈ 152 mW D | 19.4 D | 215 / 123 D |
| OpenGeMM [4] (base family) | synthesis | 16 nm, 0.675 V | ResNet-18: cycles only (9.29e8, input size unstated), no energy or accuracy | 0.531 cell | – | – | – | – |

### Table B — Recent (2024–2026) and lower-accuracy designs

| Design | Si? | Node, V | Network, precision, accuracy | Area (mm²) | Throughput | Power | µJ/inf | TOPS/W | Scaled |
|---|---|---|---|---|---|---|---|---|---|
| Kraken / CUTIE, 2024 [5] | yes | 22 nm, 0.8 V | ternary (BinarEye-derived), accuracy nr (CUTIE: 86–88 %) | nr | > 10k img/s | 110 mW | 6 A | nr | 52 / 28 µJ D |
| CUTIE [6] | post-layout | 22 nm, 0.65 V | ternary, 88 % | 7.5 | 16 TOPS peak | nr | 2.8 core | 392 avg | 39 / 20 µJ D |
| Marsellus, JSSC 2024 [7] | yes | 22 nm | ResNet-20, 2–8b, accuracy nr | nr | 637 GOPS peak | tens of mW | 28 / 21 / 12 A | 12.4 (HW layers) | per op ≈ 340 pJ/op raw vs ours 62 (v3 pre-route) D |
| Voltra, ISCAS 2026 [8] (base family) | yes | 16 nm, 0.6–1.0 V | GEMM peak, int8 | 0.654 | 0.82 TOPS peak | 171–981 mW | – | 1.60 | 0.16 TOPS/mm² area-scaled D |
| IMAGINE, 2024 [9] | yes | 22 nm FD-SOI | CNNs, 1–8b, accuracy "competitive" | nr | nr | nr | nr | 40 (system, 8b) | ≈ 2.4–4.9 TOPS/W D |
| 22 nm TD-CIM, 2025 [10] | macro | 22 nm, 0.8 V | ResNet-20, 4b, 90.72 % | nr | nr | nr | nr | 36.8 | ≈ 4.2–8.0 TOPS/W D (macro only) |
| Bankman [11] | yes | 28 nm, 0.6 V | BNN, 86 % | 4.6 | ≈ 25 img/s D | 0.094 mW | 3.8 | 772 (1b ops) | ≈ 24 µJ D |
| BinarEye [12] | yes | 28 nm, 0.66 V | BNN, 86 % | 1.4 | ≈ 104 img/s D | 1.5 mW | 14.4 | 230 (1b ops) | ≈ 77 µJ D |
| Valavi [13] | yes | 65 nm, 0.68 V | BNN, 83.3 % | 12.6 | ≈ 6.1k img/s D | 22 mW | 3.6 | 866 (1b ops) | ≈ 6.7 µJ D |

## Findings (honest reading)

1. **Same-network comparison.** We found no fabricated chip from 2024 to 2026 that reports a multi-bit ResNet-18 on CIFAR-10 with energy per inference. ChewBaccaNN, a binary post-layout design, is the only ResNet-18 CIFAR-10 point with energy.
2. **Energy at matched accuracy (≥ 91 %), after scaling.**
   - v3 pre-route at 68.5 µJ beats Jia 16 nm (123–215 µJ) and ChewBaccaNN including I/O (135–260 µJ).
   - It roughly ties Jia 65 nm if that chip was measured at 1.2 V (66 µJ).
   - The provisional routed v3, at 107.6 µJ, still beats Jia 16 nm and ChewBaccaNN including I/O. It is comparable to ChewBaccaNN core-only and loses to Jia 65 nm at 1.2 V.
   - The 0.8 V point (42.5 µJ, macros modelled) would beat all of them.
3. **Throughput and area efficiency.**
   - v3 delivers 3.6k–4.9k img/s on a full ResNet-18, and 0.39–0.84 dense-equivalent TOPS/mm² at 65 nm.
   - That is above every multi-bit digital accelerator we compared, including the base GeMM family scaled to 65 nm area (≤ 0.16). The routed ratio is about 2.4×.
   - Jia 16 nm has higher raw img/s (7,815) on a smaller network at 16 nm.
4. **Binary and ternary chips** at 83–88 % accuracy use 3–14× less scaled energy and reach higher raw TOPS. We do not beat them on energy. Our claim is energy and throughput at ≥ 91 % accuracy, not absolute energy.
5. **Threats to the comparison.**
   - Our numbers are not silicon. The routed numbers come from OpenROAD without timing-driven placement, without antenna repair, and with residual hold violations.
   - Low-voltage scaling factors are uncertain below about 0.7 V.
   - Several competitor numbers come from abstracts or secondary sources (tag A or S). They should be checked against the full papers before submission.

## References

1. R. Andri et al., "ChewBaccaNN: A Flexible 223 TOPS/W BNN Accelerator," ISCAS 2021, arXiv:2005.07137.
2. H. Jia et al., "A Programmable Heterogeneous Microprocessor Based on Bit-Scalable In-Memory Computing," IEEE JSSC 55(9), 2020.
3. H. Jia et al., "Scalable and Programmable Neural Network Inference Accelerator Based on In-Memory Computing," IEEE JSSC 57(1), 2022.
4. X. Yi et al., "OpenGeMM," ASP-DAC 2025, arXiv:2411.09543.
5. "Circuits and Systems for Embodied AI: Exploring µJ Multi-Modal Perception for Nano-UAVs on the Kraken Shield," arXiv:2410.09054, 2024.
6. M. Scherer et al., "CUTIE: Beyond PetaOp/s/W Ternary DNN Inference Acceleration with Better-than-Binary Energy Efficiency," IEEE TCAD 2022, arXiv:2011.01713.
7. F. Conti et al., "Marsellus," IEEE JSSC 59(1), 2024, arXiv:2305.08415.
8. X. Yi et al., "Voltra," ISCAS 2026, arXiv:2602.11357.
9. "IMAGINE: An 8-to-1b 22nm FD-SOI Compute-In-Memory CNN Accelerator," arXiv:2412.19750, 2024.
10. "A 22nm 96.83-TOPS/W Time-Domain Compute-in-Memory Engine Utilizing Mixed-Fidelity for Edge-AI Applications," ACM 2025, doi:10.1145/3716368.3735161.
11. D. Bankman et al., "An Always-On 3.8 µJ/86% CIFAR-10 Mixed-Signal Binary CNN Processor with All Memory on Chip in 28-nm CMOS," IEEE JSSC 54(1), 2019.
12. B. Moons et al., "BinarEye: An Always-On Energy-Accuracy-Scalable Binary CNN Processor with All Memory on Chip in 28nm CMOS," CICC 2018.
13. H. Valavi et al., "A 64-Tile 2.4-Mb In-Memory-Computing CNN Accelerator Employing Charge-Domain Compute," IEEE JSSC 54(6), 2019.
14. A. Stillmaker, B. Baas, "Scaling equations for the accurate prediction of CMOS device performance from 180 nm to 7 nm," Integration 58, 2017.
