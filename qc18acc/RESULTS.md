# QC18-ACC: results, v1–v4

This file collects the results of the project so far. Source files:

- `ARCH.md`: the v3 and v4 sections and the v4 Addendum;
- `results/power.md` (v1), `power_v2.md`, `v3.md`, `v4.md`;
- `results/pnr.md`, `pnr_v3.md`, `pnr_v4.md`;
- `results/lowv.md`, `ablation.md`, `sota.md`.

Technology: TSMC 65 nm (tcbn65gplus) with ARM memory compilers. Every number is copied from those files or derived from them (D). Each number carries a label as defined in [`results/sota.md`](results/sota.md):

- **M**: measured in simulation (RTL / GLS);
- **S**: pre-route synthesis estimate (WLM, ideal clock, incl. PTPX power on that netlist);
- **R**: post-route (OpenROAD, PrimeTime + SPEF, PTPX on the routed netlist);
- **Mod**: modelled;
- **V / A**: from a primary source text / abstract;
- **D**: derived by us.

For competitors, S means a secondary source (see sota.md). The result files use their own label sets. Section 4 maps them.

## 1. Headline

QC18-ACC runs a complete CIFAR-10 ResNet-18 on TSMC 65 nm at 91.33 % accuracy [M], bit-exact from the integer reference to the routed gate-level netlist [M]. The best routed design is v4 (`qa4_u9`): 12.685 mm² [R], 290.7 MHz tt [R], 42,360 cycles per image [M]. It delivers:

- **2.38 peak / 1.76 workload-average executed TOPS** [D];
- **0.188 / 0.139 executed TOPS/mm²** [D];
- **111.46 µJ per inference** [R+Mod], i.e. 2.31 executed TOPS/W [D].

These figures are about **8× below Valavi JSSC'19** on TOPS/mm² (≈ 1.5 peak [D from S], same node). The design is competitive only on energy per inference at ≥ 91 % accuracy, against the few chips that report it.

| | v4 pre-route | v4 routed `qa4_u9` |
|---|---|---|
| area | 7.764 mm² S | 12.685 mm² die R |
| clock (tt) | 400 MHz (fmax 465.5 S) | 290.7 MHz fmax R (power at 285.7) |
| images/s | 9,443 D | 6,863 D |
| energy / inference | 62.68 µJ S+Mod | 111.46 µJ R+Mod |
| peak / avg executed TOPS | 3.277 / 2.428 D | 2.381 / 1.764 D |
| peak / avg executed TOPS/mm² | 0.422 / 0.313 D | **0.188 / 0.139 D** |
| executed TOPS/W | 4.10 D | 2.31 D |
| dense-eq. TOPS/mm² (secondary) | 1.35 D | 0.601 D |
| DRC / antenna / hold | – | 73 R / 155 nets R / tt −0.47 ns, ss −0.71 ns R |

## 2. Workload and model

**Network.** `qc18` model **s8kd**, seed 0: a ResNet-18 (kuangliu topology, CIFAR-10) whose conv GEMM matrices are made of 8×8 quasi-cyclic blocks `B = Σ c[s] P_s`. Each block has at most two nonzero shifts, with c in {−1, +1}. The model was trained with distillation from a dense teacher.

| Quantity | Value |
|---|---|
| int8 test accuracy, s8kd seed 0 | **91.33 %** M |
| int8 test accuracy, s8kd seed 1 | 91.20 % M |
| mean ± std over 2 seeds, int8 (`qc18/RESULTS.md`) | 91.27 ± 0.09 % M |
| dense fp reference (`qc18/RESULTS.md`) | 94.91 ± 0.01 % M |
| QC weight codes, on-chip (10 b per 8×8 block) | 0.218 MB Mod |
| dense 2-b ternary equivalent | 2.791 MB Mod |
| int8 equivalent | 11.162 MB Mod |
| executed MACs / image (nonzero terms of the weight image + FC) | 128,546,560 = **257.1 Mop** Mod |
| dense-equivalent MACs / image (secondary) | 555.4 M = 1.11 GOp Mod (×4.32) |

The integer reference is `qc18/int8.py` (`IntNet`). The bit-exact chain is IntNet == compiler golden model == RTL (VCS) == gate-level netlist. The 10k-image test accuracy of the golden model equals IntNet's, 91.33 % [M], for v3 and v4.

**Metric of record** (ARCH.md, v4 Addendum):

- ops = 2 × executed MACs;
- one 8×8 QC block is at most 16 MACs, never 64;
- one ternary×int8 MAC counts as one MAC, the same as one 1b×1b MAC;
- peak = PEs × Kb × 16 × 2 × f;
- workload average = 257.1 Mop × images/s.

Dense-equivalent figures are secondary.

## 3. Architecture evolution (v1 → v4)

All four versions share the same core:

- output-stationary QC PEs, each with rotators, trit apply and accumulators;
- 3 activation buffers of 64 KiB;
- on-chip weights, params and descriptors;
- a requantising PPU and a pool + FC head;
- the same compiler pass schedule.

| Version | Change | What it fixed | Cycles/img | Area pre-route | µJ/inf at 400 MHz tt | tt fmax pre-route |
|---|---|---|---|---|---|---|
| **v1** (tag `qc18acc-v1`, `power.md`) | 8×8 PEs, one 8×8 block per PE per cycle (Kb = 1), 10-b block codes | – (baseline) | 159,982 M | 6.433 mm² S | 123.3 S+Mod | 462.9 MHz S |
| **v2** (`power_v2.md`) | macro clock gating (CKLNQD per macro); kw sliding window; PE split into sub-instances | macro deselected-clock power 60.5 → 0.0 mW [S+Mod]; array act-bank reads ×0.433 (946,644 → 409,572) [M] | 159,982 M | 6.430 S | **92.4** S+Mod (−30.9) | 463.3 S |
| **v3** (`v3.md`) | Kb = 2: two blocks per PE per cycle, fused `acc + 4 trit terms`; 128-b act words; 16 PPU lanes | v2 PE power was 68 % fixed cost per accumulator update [S]. The fix gives PE energy per block ×0.684 and cycles ×0.509 [M] | 81,438 M | 6.514 S | **68.45** S+Mod (×0.741) | 463.4 S |
| **v4** (`v4.md`) | 16 pixel rows (128 PEs); registered macro boundaries; distributed staged crossbar; 32 PPU lanes; pipelined head FC | No critical path at a macro, pre-route [S]. The xbar has no stage fed by a macro Q pin: widest fan-in 16 vs 80 in v3 [S]. Cycles ×0.520 [M] | 42,360 M | 7.764 S | **62.68** S+Mod (×0.916) | 465.5 S |

How each step held up against its prediction (ARCH.md):

- **v3** predicted ~70 µJ and measured 68.5 µJ [S+Mod]. Predicted cycles ×0.53, measured ×0.509 [M]. Predicted PE energy per block ×0.7, measured ×0.684 [S]. Control energy missed: predicted ×0.55, measured ×0.765 [S], because the xbar data volume is not cycle-proportional.
- **v4** predicted ~44k cycles and measured 42,360 [M]. Predicted 55–60 µJ and measured 62.68 µJ [S+Mod]. The reason: 54.3 of the 62.7 µJ are work-proportional (PE 36.0, PPU 11.0, act macros 7.2 µJ [S+Mod]) and do not shrink with the cycle count. Logic came in at +785.5 kGE against +600 kGE predicted [S]: the PPU doubled, and the registered boundary + crossbar add +84.3 kGE.
- **v4 routing**: the distributed crossbar, with structured placement, converges in detailed route (73 DRC [R]). v3's centralised hub did not converge (section 7).

## 4. Methods and flow

| Item | Setting |
|---|---|
| Synthesis | DC W-2024.09, wire-load mode (WireAreaLowkCon, enclosed), tcbn65gplus 200a CCS; target 3.3 ns at ss |
| Corners | ss = 0.9 V 125 C (DC target, PT), tt = 1.0 V 25 C (power, headline clocks), ff (PT only); 0.8 V tt: tcbn65gplustc0d8 (cells only, `lowv.md`) |
| Pre-route timing | PrimeTime pre-CTS, ideal clock, 0.25 ns setup uncertainty; fmax = 1 / (3.3 ns − WNS) |
| Pre-route power | PrimeTime PX tt at 2.5 ns (400 MHz) on the SAIF of the **tt-SDF gate-level simulation of CIFAR-10 test image 0**: one full inference, START..DONE |
| Macro energy | ARM datatable access energy ("+dat", `macro_dat.py`), because the macro .lib CLK energies are 0. Label Mod |
| P&R | OpenROAD 2.0-12381 (no Innovus licence), flow `flow/tsmc65/pnr` + `qc18acc/pnr/*.cfg` |
| Post-route timing | PrimeTime Q-2019.12 with def2spef SPEF (captable RC, no coupling), propagated clock; fmax = reg2reg tt / ss |
| Post-route power | PTPX tt on the routed netlist. The SAIF of image 0 is flattened onto it, so P&R-inserted nets get propagated activity (v4: 83.2 % of nets annotated [R]). The power clock is the routed tt fmax rounded down to 0.1 ns of period, with the SAIF rescaled to the same toggles per cycle |
| Verification | golden == IntNet on 1000 images (logits + all 20 maps) and on the 10k test set (logits); VCS RTL images 0..3; GLS zero-delay and tt-SDF (image 0); zero-delay GLS of every routed netlist (image 0) |
| Activity source | **one image** (test image 0) for all power numbers; ablation: two passes of that image (L2, L4) |

Label mapping used in this file:

| Source file | Its label | Label here |
|---|---|---|
| v3.md, pnr_v3.md, ablation.md §7 | [P] (PTPX power) | S pre-route / R post-route |
| v3.md, pnr_v3.md, ablation.md §7 | [Mo] | Mod |
| v4.md | [S] | S |
| pnr_v3.md, pnr_v4.md | [S] (static post-route: geometry, PT + SPEF, DRC) | R |
| pnr_v4.md | [R] (routed PTPX) | R |
| all | +dat | combined as S+Mod / R+Mod |

## 5. Results per version, pre-route and routed

TOPS columns are D. They are computed from M cycles, the Mod op count, and the row's clock and area. Routed TOPS use the routed tt fmax. Routed energy uses the power clock.

| Point | Status | f (MHz) | Area (mm²) | µJ/inf | img/s | Peak / avg exec. TOPS/mm² | Exec. TOPS/W | DRC markers | Hold after route (tt / ss) |
|---|---|---|---|---|---|---|---|---|---|
| v1 pre-route | synthesis | 400 | 6.433 S | 123.3 S+Mod | 2,500 D | 0.127 / 0.100 D | 2.09 D | – | – |
| v2 pre-route | synthesis | 400 | 6.430 S | 92.38 S+Mod | 2,500 D | 0.127 / 0.100 D | 2.78 D | – | – |
| v2 routed `qa_t1` | 23 iterations (end lowered at a plateau) | 288.3 R (power 285.7) | 8.858 R | 152.42 R+Mod | 1,802 D | 0.067 / 0.052 D | 1.69 D | 255 R | −0.132 / −0.309 ns R |
| v2 routed `qa_t1b` (improved recipe) | 17 iterations | 257.1 R (power 256.4) | 9.807 R | 142.89 R+Mod | 1,607 D | 0.054 / 0.042 D | 1.80 D | 251 R | −0.043 / −0.152 ns R |
| v3 pre-route | synthesis | 400 | 6.514 S | 68.45 S+Mod | 4,912 D | 0.252 / 0.194 D | 3.76 D | – | – |
| v3 pre-route, 0.8 V | synthesis, macros modelled | 300 | 6.514 S | 42.49 S+Mod | 3,684 D | 0.189 / 0.145 D | 6.05 D | – | – |
| v3 routed `qa3_t5b` (superseded) | stopped after iteration 4 | 295.2 R (power 294.1) | 10.384 R | 107.60 R+Mod | 3,611 D (at 294.1) | – | 2.39 D | 70,584 R | −0.394 / −0.686 ns R |
| **v3 routed `qa3_t5c`** (route of record) | **did not converge**, stopped after iteration 8 | 272.4 R (power 270.3) | 10.384 R | 108.8 R+Mod | 3,345 D | 0.107 / 0.083 D | 2.36 D | 70,675 R | −0.459 / −0.775 ns R |
| v4 pre-route | synthesis | 400 | 7.764 S | 62.68 S+Mod | 9,443 D | 0.422 / 0.313 D | 4.10 D | – | – |
| **v4 routed `qa4_u9`** (route of record) | 25 iterations, converged to 73 markers | 290.7 R (power 285.7) | 12.685 R | 111.46 R+Mod | 6,863 D | **0.188 / 0.139 D** | 2.31 D | 73 R | −0.471 / −0.710 ns R |
| v4 routed `qa4_t6` (macro gates at macros) | 25 iterations | 277.7 R (power 270.3) | 12.685 R | 112.67 R+Mod | – | – | 2.28 D | 81 R | −0.402 / −0.404 ns R |

- The superseded v3 `qa3_t5b` row leaves the TOPS/mm² columns blank. Its img/s is quoted at its power clock, 294.1 MHz, as in pnr_v3.md.
- Every routed netlist passes zero-delay GLS bit-exact for image 0, with the same cycle count as RTL [M].
- v4 `qa4_u9` fails hold at 3,500 tt / 2,827 ss endpoints [R]. 92 % of them are act-macro D pins.

Post-route penalties [D]:

| Version | Area (routed die / pre-route) | tt fmax (routed / pre-route) | Energy (routed / pre-route) |
|---|---|---|---|
| v2 `qa_t1` | ×1.38 | ×0.62 | ×1.65 R+Mod |
| v3 `qa3_t5c` | ×1.59 | ×0.59 | ×1.59 R+Mod |
| v4 `qa4_u9` | ×1.63 | ×0.62 | ×1.78 R+Mod |

## 6. QC ablation and its attribution

`results/ablation.md` §7 (Kb = 2, v3 array geometry) compares three PE variants under one flow: QC, dense TERNARY (2-b trits, no QC structure) and INT8. Each is a standalone synthesised array with GLS-SDF energy on two real passes of image 0. The system model (Mod) puts each array into the measured v3 chip, with on-chip weight SRAM sized to the weights (scenario i).

| Per inference, scenario (i) on-chip | QC | TERNARY | INT8 |
|---|---|---|---|
| array kGE | 514.3 S | 818.8 S | 3830.5 S |
| array pJ / block-op (+ weight reg), mean L2 / L4 | 3.80 S | 4.57 S | 44.64 S |
| weight capacity | 0.218 MB Mod | 2.791 MB Mod | 11.162 MB Mod |
| system energy | **65.5 µJ** Mod | 142.4 µJ Mod | 723.7 µJ Mod |
| area | 6.27 mm² Mod | 28.97 mm² Mod | 105.71 mm² Mod |
| inferences / s / mm² | 782.8 Mod | 169.6 Mod | 46.5 Mod |

**Attribution, INT8 → QC saves 658.2 µJ per inference (×11.04) [Mod]:**

| Step | Saving | Share |
|---|---|---|
| compute, INT8 → TERNARY PE (removing the multipliers) | 353.5 µJ | **53.7 %** |
| compute, TERNARY → QC PE (the QC structure in the PE) | 6.9 µJ | **1.0 %** |
| storage, int8 → 2-b trits | 227.9 µJ | 34.6 % |
| storage, trits → QC codes (12.80× fewer bits) | 70.0 µJ | 10.6 % |
| **storage total** | 297.9 µJ | **45.2 %** |

What the QC structure itself adds, beyond plain ternary weights:

- 70.0 µJ of storage saving;
- 6.9 µJ of compute saving.

**QC's benefit is storage, not compute.** The compute saving belongs to ternary weights, i.e. removing the multipliers.

At the PE level, TERNARY / QC array energy per block-op is 1.20× on the mean of the two layers [S]. Per layer it is 1.31× (L2) and 0.80× (L4): on the zero-heavy L4 pass, ternary is cheaper. The reason is the v3 QC negate encoding, (x XOR 1…1) + carry-in. It toggles with the weight sign even for x = 0 (ablation.md §7.6).

With DRAM-resident weights (scenario ii, lower bound for the dense variants), weight traffic is 82.9 % (20 pJ/b) and 94.4 % (70 pJ/b) of the INT8 → QC saving [Mod].

The Kb = 1 ablation (v2 array, §5) gives the same picture: 774.6 µJ saved, of which compute 52.9 % + 1.2 % and storage 35.2 % + 10.8 % [Mod].

## 7. State of the art (summary; full tables in [`results/sota.md`](results/sota.md))

- **TOPS/mm² (executed ops), against Valavi JSSC'19** (65 nm, 1b ops, 19 TOPS peak / 12.6 mm² ≈ 1.5 TOPS/mm² [D from S, still to check against the full paper]):
  - v4 routed is 0.188 peak / 0.139 average [D], **8.0× below** (10.8× on average);
  - v4 pre-route is 0.422 [D], 3.6× below;
  - v3 routed is 0.107 [D], 14.0× below.
- **Multi-bit digital, area-scaled to 65 nm.** v4 routed is about on par with the Voltra / GeMM family (0.16 peak TOPS/mm² int8 [D]) and below CUTIE (0.30 peak ternary [D]).
- **TOPS/W.**
  - Ours: 2.31 executed TOPS/W routed, 4.10 pre-route [D].
  - Binary / ternary chips report 230–866 [S] on their own conventions.
  - Not competitive.
- **Energy at ≥ 91 % accuracy, scaled to 65 nm / 1.0 V.**
  - v4 pre-route at 62.68 µJ beats Jia 16 nm (123–215 µJ) and ChewBaccaNN including I/O (135–260 µJ). It is about equal to Jia 65 nm at 1.2 V (66–73 µJ) [D].
  - v4 routed (111.46 µJ) and v3 routed (108.8 µJ) still beat Jia 16 nm and ChewBaccaNN including I/O. They lose to ChewBaccaNN core-only (52–100 µJ) and to Jia 65 nm at 1.2 V [D].
- **Binary / ternary chips** at 83–88 % use 1.4–17× less scaled energy than v4 routed [D].

## 8. What failed and why

**8.1 The v3 route hub** (`pnr_v3.md` §11).

- **Symptom.** v3 detailed route stalled at 70,675 markers [R] after 9 iterations, falling −4 % per 70-min iteration. 99.4 % of the markers sit in x 1400–2000 µm, at the centre of the logic band.
- **Where.** In the hub between the 48 act-macro read ports and the 64 PEs:
  - the act-buffer port logic;
  - the 128-b kw window that feeds every PE;
  - the head.

  Its cells are placed at 93–100 % utilisation [R].
- **Why the flow knobs could not fix it.**
  - Global route reports no overflow. The demand lives inside the gcells, as M2 / M3 pin access.
  - Lower density, a tighter global-placement overflow and higher GRT margins did not move the hub.
  - Padding the hub by 2 sites turned it into a global-route overflow (GRT-0119).
- **Mechanism.** 3,072 act read-data bits converge on one window register: 80 start points per bit, 24 of them macro Q pins [S]. Placement cannot spread that.
- **Fix in v4.**
  - The crossbar was made a staged register network.
  - The stages were placed structurally before global placement.
  - The v4 hub formed again with the v3 recipe (`qa4_u1`): a register pipeline gives the placer no reason to spread. Structured placement, partial blockages and an incremental global placement after DRV repair then removed it, giving 73 markers [R].

**8.2 Hold at the macros** (`pnr_v4.md` §4, `pnr_v3.md` §11.6). Every routed version fails hold at macro inputs:

- v2: tt −0.132 ns;
- v3: tt −0.459 ns;
- v4: tt −0.471 / ss −0.710 ns, with 92 % of the endpoints at act-macro D pins [R].

The global-route estimate showed hold met: ss / tt +0.017 / +0.021 ns. Two mechanisms explain the gap:

1. **Macro clock gates placed far from their macros.** CTS does not buffer the 1-sink gated net. One weight gate sat ~0.97 mm from its macro, giving 0.78–0.93 ns slew. Moving all 57 gates to their macros (`qa4_t6`) improved ss hold from −0.71 to −0.40 ns [R].
2. **OpenROAD's pre-route clock latency estimate is off by about 0.4 ns at the leaves.** On the worst act-macro D path:
   - OpenROAD estimates slack +0.243 ns;
   - PT + SPEF gives −0.22 ns.

   So the repair never saw the violation.

A margin run (`qa4_u10`, +0.3 ns on all macros) needed 40,100 hold buffers and 3 h 42 min of repair. Its detailed route was stopped after iteration 4 at 47,655 markers and left unfinished. **Post-route hold closure is open.**

**8.3 OpenROAD limits in this build.**

- No Innovus licence.
- `repair_antennas` segfaults, so there is no antenna repair (v4: 155 antenna nets).
- `repair_timing -setup` repairs only the worst endpoint by default.
- The SPEF reader stops at the netlist's `SYNOPSYS_UNCONNECTED` nets, so OpenROAD cannot time post-route. PrimeTime is used instead.
- A post-route ECO re-routes the whole design (~7.5 h).
- Detailed route peaks at 25.5 GB of 30 GB.
- Global placement ignores instance padding, and incremental global placement ignores hard blockages.
- TritonCTS looped on one clock net (`qa4_u8`).
- TritonCTS uses CKBD16 for the tree levels.
- M1 MINIMUMCUT / LEF57 rules are not checked, and there is no metal fill.

**8.4 Post-route clock and area penalties** (section 5 table).

- **Clock.** Routed tt fmax is ×0.59–0.62 of pre-route in every version. The v4 critical path is now the single-cycle ~1.2 mm wire from the central sequencer / AGU to the far act-macro address flops [R]. The registered boundary moved the flops to the macros, so the request wire became the long hop. Fix: a register stage on that path or replicated AGU slices. Not done.
- **Area.** The die grows ×1.63 [D]. Cells after P&R are 3.951 mm² against 2.307 mm² of DC logic (×1.71 [R]), from about 101k DRV-repair buffers and 24.1k hold buffers, at ~0.67 placement utilisation in a 1,600 µm logic band.
- **Energy.** Energy grows ×1.78 [R+Mod]:
  - the clock tree adds 17.1 µJ;
  - P&R glue buffers add 15.7 µJ;
  - leakage of the longer cycle adds 4.4 µJ.

## 9. Threats to validity

- **Not silicon.** Pre-route numbers use a wire-load model and an ideal clock. Routed numbers come from an open-source flow with residual DRC (73), 155 antenna nets and **failing hold**. A routed netlist that fails hold would not work at any clock without an ECO. Our routed GLS is zero-delay only.
- **v3 routed numbers are of an unconverged route** (70,675 markers). The wire RC differs from a finished route.
- **One image.** All power numbers use the activity of test image 0. The ablation uses two passes of it.
- **Macro energy is modelled** from datatables (Mod). The kit has no 0.8 V macro corner, so every 0.8 V macro number is modelled.
- **SPEF** is geometric (captable RC, no coupling). 16.8 % of the v4 routed nets carry propagated, not simulated, activity.
- **Op convention.** Executed ops count a ternary×int8 MAC like a 1b×1b MAC. This flatters us against binary chips. Average TOPS depends on the term density of this one network (0.913) [M].
- **Ablation** is a model (Mod) built on standalone arrays and a linear per-bit SRAM model. INT8 has no zero-gating, and the INT8 weights come from a different network (dense_s0).
- **Competitors.** Several numbers are from abstracts or secondary sources (A / S), including every Valavi number. The scaling rules are uncertain below ~0.7 V. Throughput is not node-normalised.
- **Accuracy** is from 2 training seeds. This design uses seed 0 (91.33 %); seed 1 gives 91.20 %.

## 10. The v4 bottleneck

Area per peak executed MAC/cycle (v4.md §8, 4,096 MACs/cycle):

| Group | µm² per MAC/cycle, pre-route | Share |
|---|---|---|
| macros (act 650.7, weight 518.6, param + desc 163.0, registered boundary 13.8) | 1346.1 S | 71.0 % |
| PE (adders 153.2, rotators 111.6, acc + shadow regs 68.4, muxes 23.5, operand regs 3.7, clock gates 2.0) | 362.5 S | 19.1 % |
| PPU (+ drain) | 132.3 S | 7.0 % |
| xbar | 36.9 S | 1.9 % |
| control | 17.6 S | 0.9 % |
| **total, pre-route** | **1895.5 S** (≈ 1896) | 100 % |
| **total, routed die** (12.685 mm² / 4,096) | **3097 D** (×1.63) | |

The target needs 533 µm² per MAC/cycle in total: 1.5 executed TOPS/mm² peak at 400 MHz means 2 × 400 MHz / 1.5 TOPS/mm² [D].

**Logic-only asymptote**, peak TOPS/mm² = 2f / a, with a = logic area per MAC/cycle:

- With a = 549.3 µm² (PE + PPU + xbar + control, pre-route) at 400 MHz: **≈ 1.46 TOPS/mm²** [D]. This is with zero memory area, and it is below 1.5. **The current PE organisation cannot reach 1.5 executed TOPS/mm² at 400 MHz at any array size.** Scaling the PE count only amortises the macros.
- The PE alone (362.5 µm²) gives 2.21 TOPS/mm² [D].
- Qualifications [D]:
  - The break-even clock for the 549.3 µm² logic is ≈ 412 MHz. At the pre-route tt fmax of 465.5 MHz the asymptote is 1.70.
  - The routed clock is 290.7 MHz, and routed logic is ×1.71 larger. So routed, the asymptote is far below 1.5.
  - The claim therefore holds at the clocks this flow achieves. It is not a statement about every clock.

What v5 needs, by v4.md §8:

- (a) far more MACs per macro area: 4× the PEs on the same memories gives 337 µm² per MAC/cycle of macros;
- (b) a smaller PE per MAC: adders + rotators are 265 of the 362 µm²;
- (c) a faster clock: at 800 MHz the budget is 1,066 µm²;
- routing that does not cost ×1.63 in area and ×0.62 in clock.

## 11. Reproduction

All commands are in [`README.md`](README.md):

- compiler, RTL, implementation and GLS (v1 / v2): sections "Compiler + golden model", "RTL", "Implementation, TSMC 65 nm";
- v3 and v4: sections "v3", "v4" (`QA_V=3` / `QA_V=4`);
- array ablation (incl. `QAB_KB=2`): section "Array ablation";
- place & route: sections "Place & route, OpenROAD", with "v3 P&R and the improved recipe" and "v4 P&R"; command lists are also at the end of `results/pnr_v3.md` §12 and `results/pnr_v4.md` §10;
- 0.8 V: `results/lowv.md`.

Kit-derived views stay on the build hosts. The repo keeps scripts and summaries.

## Inconsistencies found between files (not resolved here)

1. **Detailed-route iteration count of `qa4_u9`.** `pnr_v4.md` §2 says "routed, 24 iterations". §0 and §3 say 25 iterations: iterations 0–24.
2. **v3 routed reference inside `pnr_v4.md`.** §0 uses `qa3_t5c` (108.8 µJ). §6 says "v3 routed: 107.6 uJ (x1.57); v4 routed 111.5 uJ is x1.04 of v3 routed", which is `qa3_t5b`. Against `qa3_t5c` the ratio is ×1.024 [D]. Similarly, §5's "v3 improved x0.64" (routed / pre-route tt) is `qa3_t5b`; `qa3_t5c` gives ×0.59.
3. **ARCH.md v4 "Why"** quotes the v3 routed clock as tt 295 / ss 185 MHz. That is `qa3_t5b`. The route of record `qa3_t5c` is 272.4 / 148.9 MHz.
4. **Previous sota.md, "v2 routed (improved recipe)".** It listed 285.7 MHz / 141.2 µJ. `qa_t1b` only reaches 257.1 MHz tt, and `pnr_v3.md` §6 calls the 3.5-ns run "not met, comparison only". sota.md now uses 257.1 / 256.4 MHz and 142.89 µJ.
5. **Previous sota.md, provisional v3 row.** It listed 3,610 img/s at 294 MHz. `pnr_v3.md` gives 3,611 at 294.1 MHz (rounding; the row is superseded).
6. **Previous sota.md, Marsellus.** It printed "≈ 340 pJ/op raw vs ours 62 (v3 pre-route)". Ours is 68.45 µJ / 1.11 GOp = 0.062 pJ (62 fJ) per dense-eq. op, so the unit is wrong by 1000×. The Marsellus op count behind "340" is not in our files. sota.md now prints 0.34 pJ/op and flags it.
7. **Previous sota.md, scaling rule.** Jia 65 nm (66 / 147 µJ) and Valavi (6.7 µJ) do not match the classical rule (73 / 146 µJ and 7.8 µJ [D]), and the column does not say which rule was used. Both are now shown.
8. **Label sets differ between files.**
   - `pnr_v3.md` / `pnr_v4.md` use [S] for post-route static results; sota.md's S means pre-route synthesis.
   - `v3.md` / `pnr_v3.md` / `ablation.md` §7 use [P] / [Mo].
   - The previous sota.md labelled pre-route PTPX as M, and used "S" for competitor secondary sources (as does the task brief: "S (secondary source)").
   - sota.md now defines S per context; section 4 gives the mapping.
9. **Stale "not done" statements.**
   - ARCH.md v3 [impl] ("The ablation rerun at Kb = 2 is not done (open)") and `v3.md` §6 are contradicted by `ablation.md` §7, which is done.
   - `v4.md` §10 ("Not done: P&R of v4") is superseded by `pnr_v4.md`.
10. **"Cannot reach 1.5 at any scale"** (task brief / section 10). The logic-only asymptote is 1.46 TOPS/mm² only at 400 MHz. At the pre-route tt fmax (465.5 MHz) it is 1.70 [D]. The statement holds at 400 MHz and below about 412 MHz.
