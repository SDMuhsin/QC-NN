# qc18acc vs state of the art

Status: draft, revised for the executed-op metric. Every routed row is an OpenROAD result, not silicon. The v3 routed row is `qa3_t5c`: its detailed route **did not converge** (70,675 DRC markers after 9 iterations, `pnr_v3.md` §11). The v4 routed row is `qa4_u9`: 73 DRC markers and 155 antenna nets, with hold failing at the macro inputs (`pnr_v4.md` §4). Project summary: [`../RESULTS.md`](../RESULTS.md).

## Conventions

**Workload (ours).** CIFAR-10 ResNet-18 (kuangliu topology), model `s8kd` seed 0. Accuracy is 91.33 % on the 10k test set [M]. The golden model, RTL and GLS are bit-exact against `qc18/int8.py`.

**Metric of record: executed ops** (ARCH.md, v4 Addendum).

- ops = 2 × executed MACs.
- An 8×8 QC block executes 8 outputs × ≤ 2 nonzero terms, so at most 16 MACs, never 64.
- One ternary×int8 MAC counts as **one MAC (2 ops)**, the same as one 1b×1b MAC in a binary chip.
- Executed MACs per image: **128,546,560**, i.e. **257.1 Mop/image** [Mod]. This counts the nonzero terms of the weight image as the array consumes them (`compile4/ops.py`, v4.md §7). The count is the same for v2, v3 and v4, because v3 and v4 use the v2 weight codes word for word.
- **Peak** executed TOPS = PEs × Kb × 16 × 2 × f:
  - v2: 2,048 ops/cycle;
  - v3: 4,096 ops/cycle;
  - v4: 8,192 ops/cycle.
- **Workload-average** executed TOPS = 257.1 Mop × images/s. In v4 this is 0.741 of peak [M]: the array is busy 81.1 % of the time and the term density is 0.913.
- **Executed TOPS/W** = 257.1 Mop / energy per inference. This is a workload average. We have no peak-power measurement.
- **TOPS/mm²** uses the full area: the pre-route cell + macro area, or the routed die.
- **Dense-equivalent** ops (555.4 M MAC = 1.11 GOp/image [Mod], 4.32× the executed count) are **secondary**. They are labelled "dense-eq." wherever they appear. Equivalent-op metrics were criticised for CirCNN and PermDNN, and this design would inherit that criticism.

**Labels.**

| Label | Meaning |
|---|---|
| M | measured in simulation on our flow: RTL / GLS cycle counters, bit-exact checks, accuracy |
| S | *our designs:* pre-route synthesis estimate, i.e. DC area, PrimeTime timing and PrimeTime PX power on the wire-load-model netlist with the GLS SAIF, ideal clock. *Competitors:* **secondary source**, not yet checked against the full paper |
| R | post-route: OpenROAD die / geometry, PrimeTime + def2spef SPEF timing, PrimeTime PX on the routed netlist |
| Mod | modelled: op counts from the weight image, ARM-datatable macro access energy ("+dat"), 0.8 V macro scaling |
| V | from the primary source text or table |
| A | from the abstract only |
| D | derived by us from tagged numbers. The arithmetic is given or obvious from the row |

Change from the previous draft:

- Pre-route PTPX power was labelled M ("M/S"). It is now S, because it rests on the wire-load-model netlist.
- Competitor numbers that the draft left untagged are now tagged S until they are checked.

**Normalisation to 65 nm, 1.0 V.**

- Energy uses two rules, and both are reported:
  - **Stillmaker & Baas** (Integration 58, 2017, Table 5). Bracket: 28 nm ≈ 32 nm HP, 22 nm ≈ 20 nm HP.
  - **Classical**, (65/L)·(1.0/V)².
- Area uses the Stillmaker Table 4 factor: ×7.9 for 16 nm, ×7.1 for 20/22 nm, ×3.3 for 28/32 nm.
- Throughput is **not** normalised for speed. This favours newer-node competitors.

## Our design points

All points run the same network at 91.33 % [M] and are bit-exact in RTL and GLS. Routed GLS is zero-delay only.

Clocks and energy:

- Pre-route rows: 400 MHz tt, which is below the pre-route tt fmax of 463–466 MHz [S].
- Routed rows: throughput and TOPS are at the routed **tt reg2reg fmax** [R]. Energy is the PTPX run at the power clock, which is that fmax rounded down to 0.1 ns of period. The clock is given in the table.

All TOPS columns are D. They are computed from:

- the M cycle counts;
- the Mod op count;
- the row's clock and area.

The v3 and v4 values agree with v4.md §7 and pnr_v4.md §0/§8, to their printed digits.

### Primary metrics (executed ops)

| Point | f for TOPS (MHz) | Area (mm²) | µJ/inf | **Peak exec. TOPS** | **Avg exec. TOPS** | **Exec. TOPS/W** (avg) | **Peak exec. TOPS/mm²** | **Avg exec. TOPS/mm²** |
|---|---|---|---|---|---|---|---|---|
| v2, pre-route | 400 | 6.430 S | 92.38 S+Mod | 0.819 D | 0.643 D | 2.78 D | 0.127 D | 0.100 D |
| v2, routed `qa_t1` (v2 recipe) | 288.3 R | 8.858 die R | 152.42 R+Mod | 0.590 D | 0.463 D | 1.69 D | 0.067 D | 0.052 D |
| v2, routed `qa_t1b` (improved recipe) | 257.1 R | 9.807 die R | 142.89 R+Mod | 0.527 D | 0.413 D | 1.80 D | 0.054 D | 0.042 D |
| v3, pre-route | 400 | 6.514 S | 68.45 S+Mod | 1.638 D | 1.263 D | 3.76 D | 0.252 D | 0.194 D |
| v3, pre-route, 0.8 V | 300 | 6.514 S | 42.49 S+Mod (macros V²) | 1.229 D | 0.947 D | 6.05 D | 0.189 D | 0.145 D |
| v3, routed `qa3_t5c` (**route did not converge**: 70,675 DRC) | 272.4 R | 10.384 die R | 108.8 R+Mod | 1.116 D | 0.860 D | 2.36 D | 0.107 D | 0.083 D |
| **v4, pre-route** | 400 | 7.764 S | 62.68 S+Mod | **3.277 D** | **2.428 D** | **4.10 D** | **0.422 D** | **0.313 D** |
| **v4, routed `qa4_u9`** (73 DRC, hold failing) | 290.7 R | 12.685 die R | 111.46 R+Mod | **2.381 D** | **1.764 D** | **2.31 D** | **0.188 D** | **0.139 D** |

### Operating point and secondary (dense-equivalent) metrics

| Point | Corner | Power clock (MHz) | Cycles/img | img/s at f for TOPS | Latency | Power (mW) | Dense-eq. TOPS (secondary) | Dense-eq. TOPS/W (secondary) | Dense-eq. TOPS/mm² (secondary) |
|---|---|---|---|---|---|---|---|---|---|
| v2, pre-route | tt 1.0 V | 400 | 159,982 M | 2,500 D | 400 µs D | 231.0 S+Mod | 2.78 D | 12.0 D | 0.43 D |
| v2, routed `qa_t1` | tt 1.0 V | 285.7 | 159,982 M | 1,802 D | 555 µs D | 272.2 R+Mod | 2.00 D | 7.3 D | 0.23 D |
| v2, routed `qa_t1b` | tt 1.0 V | 256.4 | 159,982 M | 1,607 D | 622 µs D | 229.0 R+Mod | 1.79 D | 7.8 D | 0.18 D |
| v3, pre-route | tt 1.0 V | 400 | 81,438 M | 4,912 D | 204 µs D | 336.2 S+Mod | 5.46 D | 16.2 D | 0.84 D |
| v3, pre-route, 0.8 V | tt 0.8 V | 300 | 81,438 M | 3,684 D | 271 µs D | 156.5 S+Mod | 4.09 D | 26.1 D | 0.63 D |
| v3, routed `qa3_t5c` | tt 1.0 V | 270.3 | 81,438 M | 3,345 D | 299 µs D | 361.0 R+Mod | 3.72 D | 10.2 D | 0.36 D |
| v4, pre-route | tt 1.0 V | 400 | 42,360 M | 9,443 D | 106 µs D | 591.9 S+Mod | 10.49 D | 17.7 D | 1.35 D |
| v4, routed `qa4_u9` | tt 1.0 V | 285.7 | 42,360 M | 6,863 D | 146 µs D | 751.8 R+Mod | 7.62 D | 9.97 D | 0.60 D |

Notes:

- All energy is on-chip. Weights and activations are fully resident, so there is no DRAM traffic per inference. The ablation (`ablation.md`) has a DRAM what-if.
- The routed v2 / v3 / v4 designs fail hold at the macro inputs after route:
  - v2 `qa_t1`: tt −0.132 ns [R];
  - v3 `qa3_t5c`: tt −0.459 ns [R];
  - v4 `qa4_u9`: tt −0.471 ns / ss −0.710 ns [R].

  No post-route hold ECO was run. The routed timing and power assume that an ECO would fix hold at negligible cost. That is not shown.
- 0.8 V macros are modelled, because the kit's memory compilers have no 0.8 V corner.
- The previous draft's v3 routed row was `qa3_t5b`: 294 MHz, 107.6 µJ, iteration 4, 70,584 DRC. It is superseded by `qa3_t5c` as the route of record. Neither route converges.
- The previous draft's "v2 routed (improved recipe)" row was 285.7 MHz / 141.2 µJ. `qa_t1b` does not meet that clock: its tt fmax is 257.1 MHz [R], and pnr_v3.md §6 calls the 3.5-ns run "comparison only". The row now uses its own fmax, 257.1 MHz, and its power clock, 256.4 MHz (142.89 µJ).

## Competitors

The op convention matters more than anything else in this comparison:

- Binary chips count one 1b×1b MAC as 2 ops.
- We count one ternary×int8 MAC as 2 ops.
- Dense int8 chips count one int8×int8 MAC as 2 ops.

So an equal TOPS figure means very different arithmetic per op. Our convention is the generous one for us: an int8 activation operand is counted the same as a 1-bit one.

### Table A — Same or similar task, accuracy ≥ 91 % on CIFAR-10

| Design | Si? | Node, V | Network, precision, accuracy | Op convention; peak or average | Area (mm²) | img/s | Power | µJ/inf (reported) | µJ/inf at 65 nm, 1.0 V (Stillmaker / classical) |
|---|---|---|---|---|---|---|---|---|---|
| ChewBaccaNN [1] | post-layout | 22 nm FDX, 0.4 V | **ResNet-18**, binary (IR-Net), 91.5 % S | 1b×1b binary ops; 223 TOPS/W in the title A. Peak or average is not recorded in our notes (check) | 0.7 S | 324 S | 2.4 mW S | 7.3 incl. I/O V | 260 / 135 (core only ≈ 100 / 52) D |
| Jia, 65 nm [2] | yes | 65 nm, 1.2 V or 0.85 V (unclear) | 11-layer CNN, 4b/4b, 92.4 % S | bit-scalable IMC; op normalisation (per 1b or per 4b op) not recorded (check); not used here | 13.5 S | 23 S | ≈ 2.4 mW D | 105.2 V | 66 (if 1.2 V) – 147 (if 0.85 V) D; the draft does not say which rule (see RESULTS.md, Inconsistencies). Classical gives 73 / 146 D |
| Jia, 16 nm [3] | yes | 16 nm, 0.8 V | 11-layer CNN, 4b/4b, 91.51 % S | as [2]; not used here | nr | **7,815** S | ≈ 152 mW D | 19.4 D | 215 / 123 D |
| OpenGeMM [4] (base family) | synthesis | 16 nm, 0.675 V | ResNet-18: cycles only (9.29e8 S, input size unstated); no energy or accuracy | int8×int8 = 2 ops; peak (GeMM array) | 0.531 cell S | – | – | – | – |

### Table B — Recent (2024–2026) and lower-accuracy designs

| Design | Si? | Node, V | Network, precision, accuracy | Op convention; peak or average | Area (mm²) | Throughput | Power | µJ/inf | TOPS/W (own convention) | Scaled (65 nm, 1.0 V) |
|---|---|---|---|---|---|---|---|---|---|---|
| Kraken / CUTIE, 2024 [5] | yes | 22 nm, 0.8 V | ternary (BinarEye-derived), accuracy nr (CUTIE: 86–88 % S) | ternary ops; TOPS not used here | nr | > 10k img/s A | 110 mW A | 6 A | nr | 52 / 28 µJ D |
| CUTIE [6] | post-layout | 22 nm, 0.65 V | ternary, 88 % S | ternary×ternary MAC = 2 ops; whether zero operands are counted is not checked. 16 TOPS is **peak**, 392 TOPS/W is **average** | 7.5 S | 16 TOPS peak S | nr | 2.8 core S | 392 avg S | 39 / 20 µJ D; peak 16 / (7.5 × 7.1) = 0.30 TOPS/mm² D |
| Marsellus, JSSC 2024 [7] | yes | 22 nm | ResNet-20, 2–8b, accuracy nr | ops at the layer precision (2–8 b); 637 GOPS **peak**; 12.4 TOPS/W is the average over the HW-mapped layers | nr | 637 GOPS peak A | tens of mW A | 28 / 21 / 12 A | 12.4 (HW layers) A | per op ≈ 0.34 pJ/op raw D (the draft printed "340 pJ"; unit corrected, see Inconsistencies) vs ours 0.24 pJ per executed op (v4 pre-route) / 0.43 (v4 routed) D |
| Voltra, ISCAS 2026 [8] (base family) | yes | 16 nm, 0.6–1.0 V | GEMM peak, int8 | int8×int8 = 2 ops, **peak** | 0.654 S | 0.82 TOPS peak S | 171–981 mW S | – | 1.60 S | 0.16 TOPS/mm² area-scaled D |
| IMAGINE, 2024 [9] | yes | 22 nm FD-SOI | CNNs, 1–8b, accuracy "competitive" A | 8b ops for the 40 TOPS/W figure; peak (system) | nr | nr | nr | nr | 40 (system, 8b) A | ≈ 2.4–4.9 TOPS/W D |
| 22 nm TD-CIM, 2025 [10] | macro | 22 nm, 0.8 V | ResNet-20, 4b, 90.72 % A | 4b ops; macro-level peak | nr | nr | nr | nr | 36.8 A | ≈ 4.2–8.0 TOPS/W D (macro only) |
| Bankman [11] | yes | 28 nm, 0.6 V | BNN, 86 % S | 1b×1b ops; whether 772 is peak or average is not recorded (check) | 4.6 S | ≈ 25 img/s D | 0.094 mW S | 3.8 S | 772 (1b ops) S | ≈ 24 µJ D |
| BinarEye [12] | yes | 28 nm, 0.66 V | BNN, 86 % S | 1b×1b ops; peak or average not recorded (check) | 1.4 S | ≈ 104 img/s D | 1.5 mW S | 14.4 S | 230 (1b ops) S | ≈ 77 µJ D |
| Valavi [13] | yes | 65 nm, 0.68 V | BNN, 83.3 % S | 1b×1b MAC = 2 ops, **peak** | 12.6 S | 19 TOPS peak S; ≈ 6.1k img/s D | 22 mW S | 3.6 S | 866 (1b ops) S | ≈ 6.7 µJ D (rule not stated in the draft; classical (1/0.68)² gives 7.8 D) |

### Table C — Executed TOPS/mm² against Valavi JSSC'19 (same node, no area scaling)

| Design | Node | Peak TOPS | Area (mm²) | Peak TOPS/mm² | Workload-avg TOPS/mm² | Valavi / design (peak) |
|---|---|---|---|---|---|---|
| **Valavi JSSC'19 [13]** (1b ops) | 65 nm | 19 S | 12.6 S | **≈ 1.5 D** (19 / 12.6 = 1.51) | nr | 1 |
| qc18acc v4, pre-route (executed ops) | 65 nm | 3.277 D | 7.764 S | 0.422 D | 0.313 D | 3.6× D |
| **qc18acc v4, routed `qa4_u9`** (executed ops) | 65 nm | 2.381 D | 12.685 R | **0.188 D** | **0.139 D** | **8.0× D** (10.8× on our average) |
| qc18acc v3, routed `qa3_t5c` (route did not converge) | 65 nm | 1.116 D | 10.384 R | 0.107 D | 0.083 D | 14.0× D |

The Valavi values (19 TOPS, 12.6 mm², 866 TOPS/W, 22 mW, 0.68 V) come from a secondary source (tag S). **They must still be checked against the full JSSC paper** before submission. Specific points to check:

- the voltage and clock at which 19 TOPS is reached;
- whether 12.6 mm² is the die or the core;
- how the paper counts ops.

## Findings (honest reading, executed-op metric)

1. **The metric change costs 4.32×.** Under executed ops, every TOPS figure in the previous draft falls by a factor of 4.32: 1.11 GOp → 257.1 Mop per image [Mod]. v3 routed was 0.39 dense-eq. TOPS/mm² in the draft. On executed ops it is 0.107 peak / 0.083 average [D].
2. **Area efficiency: about 8× below Valavi after routing.**
   - v4 routed `qa4_u9` reaches 0.188 peak / 0.139 average executed TOPS/mm² [D]. Valavi JSSC'19 reaches ≈ 1.5 TOPS/mm² peak [D from S] in the same 65 nm node. We are **8.0× below** on peak and 10.8× on our workload average.
   - Pre-route v4 is 0.422 [D], still 3.6× below.
   - The gap comes from three penalties:
     - the macros take 71 % of the pre-route area per MAC [S];
     - routing costs ×1.63 in area per MAC [R];
     - routing costs ×0.62 in tt clock [R].

     RESULTS.md, "The v4 bottleneck", shows that the current logic per MAC alone caps peak executed TOPS/mm² at ≈ 1.46 at 400 MHz [D]. The 1.5 target of the ARCH Addendum therefore cannot be reached by scaling the PE count.
   - The ARCH target was > 1.5 executed TOPS/mm² routed. It is not met.
3. **Against multi-bit digital accelerators**, area-scaled to 65 nm:
   - v4 routed (0.188 peak [D]) is only ≈ 1.2× the Voltra / GeMM base family (0.16 peak, int8×int8 ops [D]).
   - v3 routed (0.107) is below Voltra.
   - CUTIE scaled is 0.30 peak TOPS/mm² [D] in ternary ops. It is above v4 routed.

   The draft said our throughput per area was "above every multi-bit digital accelerator we compared". Under the executed-op metric, that is no longer supported: v4 routed is on par with Voltra and below CUTIE.
4. **Energy efficiency (TOPS/W) is not competitive.**
   - Our executed TOPS/W:
     - v4 pre-route 4.10 [D];
     - v4 routed 2.31 [D];
     - v3 routed 2.36 [D].
   - Competitors on their own conventions, without voltage normalisation:
     - Valavi 866 (1b ops) [S];
     - Bankman 772 [S];
     - CUTIE 392 [S];
     - BinarEye 230 [S];
     - IMAGINE 40 (8b) [A];
     - Marsellus 12.4 [A].
   - We are about two orders of magnitude below the binary and ternary chips (100–375× [D]), 17× below IMAGINE and 5× below Marsellus [D]. Their voltages are not normalised.
   - Our energy is dominated by the PE array, with its int8 activations and 20-b accumulators, and by the PPU. It is not dominated by the multiplies that executed-op counting removes.
5. **Energy at matched accuracy (≥ 91 %), after scaling.** This is the comparison that still favours us.
   - v4 pre-route, 62.68 µJ [S+Mod]:
     - beats Jia 16 nm (123–215 µJ [D]);
     - beats ChewBaccaNN including I/O (135–260 µJ [D]);
     - is about equal to Jia 65 nm if that chip was measured at 1.2 V (66 µJ [D], or 73 µJ classical [D]).
   - v4 routed, 111.46 µJ [R+Mod], and v3 routed, 108.8 µJ [R+Mod]:
     - still beat Jia 16 nm on both scaling rules;
     - still beat ChewBaccaNN including I/O;
     - lose to ChewBaccaNN core-only (52–100 µJ [D]);
     - lose to Jia 65 nm at 1.2 V (66–73 µJ);
     - beat Jia 65 nm if it ran at 0.85 V (146–147 µJ).
   - The v3 0.8 V point (42.49 µJ, macros modelled, pre-route) would beat all of them. It has not been routed.
6. **Same-network comparison.** We found no fabricated chip from 2024 to 2026 that reports a multi-bit ResNet-18 on CIFAR-10 with energy per inference. ChewBaccaNN, a binary post-layout design, is the only ResNet-18 CIFAR-10 point with energy.
7. **Binary and ternary chips** at 83–88 % accuracy use 1.4–17× less scaled energy than v4 routed: 6.7–77 µJ vs 111.46 µJ [D]. They also reach far higher TOPS/W. Our claim is limited to energy per inference at ≥ 91 % accuracy against the few chips that report it. It does not extend to TOPS, TOPS/W or TOPS/mm².
8. **Threats to the comparison.**
   - Our numbers are not silicon. The routed numbers come from OpenROAD:
     - without antenna repair (155 antenna nets);
     - with 73 residual DRC markers;
     - with hold failing at the macro inputs.

     v3 routed did not converge at all.
   - Our op convention counts a ternary×int8 MAC like a 1b×1b MAC. This flatters us against binary chips.
   - Low-voltage scaling factors are uncertain below about 0.7 V.
   - Several competitor numbers come from abstracts (A) or secondary sources (S), including every Valavi number used in Table C. They must be checked against the full papers before submission.

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
