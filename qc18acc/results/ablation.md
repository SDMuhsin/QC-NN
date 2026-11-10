# QC18-ACC array ablation: QC vs TERNARY vs INT8 PE (same array, pipeline, dataflow)

Scripts: `qc18acc/ablation/` (README: qc18acc/README.md, "Array ablation").  Flow as `impl/` (DC W-2024.09, tcbn65gplus, WLM WireAreaLowkCon enclosed, 3.3 ns at ss, `impl/constraints.sdc`; PT ss / tt / ff pre-CTS), GLS VCS with the DC tt SDF (ideal clock, 0.5 ns input delay, timing checks on) at 2.5 ns, PT PX tt 1.0 V 25 C with the synthesis WLM over the SAIF of the PE busy window.  Summaries: `results/ablation/`.

Sections 1-6: Kb = 1 (v2 array, one block per PE per cycle).  Section 7: Kb = 2 (v3 array, two blocks per PE per cycle; `report3.py`).

## 1. Variants

| | QC (v2, unchanged) | TERNARY | INT8 |
|---|---|---|---|
| PE RTL | `hw/rtl/qa_pe.sv` (2 rotators, trit + 2-term add, accumulate) | `ablation/rtl/qab_pe.sv` V=1: 8 trit-selects + 8-term adder tree per lane | V=2: 8 signed 8x8 multipliers + adder tree per lane |
| weight bits / block (per PE / column) | 10 | 128 (64 trits x 2 b) | 512 (64 x int8) |
| weight bits into the array / cycle | 80 | 1024 | 4096 |
| lane sum / accumulator | 10 b / 20 b | 12 b / 21 b | 19 b / 32 b |

Identical in all three: 8 x 8 PEs (rows = 8 output pixels, columns = 8 output-channel groups of 8), one 8x8 block per PE per cycle, output-stationary accumulators (first step overwrites), capture into the shadow register on the last step, shadow chain towards the column head, the input pipeline register (x 512 b, weights 8 x WB b, vld / first / last / shift; `rtl/qab_top.sv`).  TERNARY accumulator: the worst case of an arbitrary ternary 3x3x512 conv is 4608 x 128 = 589 824 < 2^20, i.e. 21 b signed (QC: 2 x 576 x 127 < 2^18, v2 uses 20 b).

Stream (`vectors.py`): s8kd_s0 test image 0, the REAL v2 array inputs (golden model up to the pass, then `golden.gather_window`: v2 tap order kh, cb, kw, kw window, padding lanes zero), 2304 steps per point:
- L2 = blocks.3.c1 (layer 2, K = 144, 16 tiles): K 144 tiles 16 steps 2304 x_zero 0.570 x_mean 2.47 qc_zero_coef 0.7715 int8_zero 0.0164 int8_mean_abs 21.40 max_acc qc 536 int8 42339 golden_check PASS
- L4 = blocks.7.c1 (layer 4, K = 576, 4 tiles): K 576 tiles 4 steps 2304 x_zero 0.940 x_mean 0.28 qc_zero_coef 0.7611 int8_zero 0.0149 int8_mean_abs 21.95 max_acc qc 359 int8 49560 golden_check PASS
- weights: QC = the pass's v2 weight words; TERNARY = the same blocks expanded (same math); INT8 = dense_s0 (`/tmp/root/qc18/final/dense_s0/best.pt`) conv of the same layer, BN folded (`qc18.verify.fold`), symmetric per-output-channel int8; INT8c (control) = the s8kd blocks as int8 (same math as QC).

## 2. Area and timing (standalone, DC 3.3 ns ss)

| | QC | TERNARY | INT8 |
|---|---|---|---|
| array (u_array) kGE | 393.7 | 513.1 | 2281.2 |
| one PE (mean of 64) kGE | 6.13 | 7.99 | 35.21 |
| array mm2 | 0.567 | 0.739 | 3.285 |
| input pipeline registers (x + weights + control) kGE | 3.0 | 8.6 | 27.9 |
| array vs QC | 1.00x | 1.30x | 5.79x |
| fmax ss MHz (WNS ns) | 303.7 (+0.007) | 303.3 (+0.003) | 302.4 (-0.006) |
| fmax tt MHz (WNS ns) | 469.6 (+1.171) | 469.7 (+1.171) | 466.7 (+1.157) |
| fmax ff MHz (WNS ns) | 667.6 (+1.802) | 669.7 (+1.807) | 660.8 (+1.787) |
| fmax probe: synthesized at 2.0 ns, ss / tt MHz (top kGE) | 494.7 / 729.9 (565) | 466.0 / 693.7 (747) | 351.1 / 534.2 (2520) |

At the 3.3 ns target DC closes timing for every variant (INT8: ss WNS -6 ps, i.e. 302 MHz; DC sizes to the constraint), so the 3.3 ns fmax is the target, not a limit; the 2.0 ns probe (same flow, `QAB_PERIOD=2.0 remote.sh syn <v>`, area grows) shows the achievable ss / tt clock.

Worst ss paths: QC `u_wrap/w_reg_44_/CP -> u_wrap/g_qc_u_array/g_col_4__g_row_1__u_pe/sh_out_reg_79_/D`; TERNARY `u_wrap/x_reg_145_/CP -> u_wrap/g_d_u_array/g_col_0__g_row_2__u_pe/sh_out_reg_146_/D`; INT8 `u_wrap/w_reg_2153_/CP -> u_wrap/g_d_u_array/g_col_4__g_row_6__u_pe/sh_out_reg_60_/D`.  v2 in-chip QC array: 0.571 mm2 (396.4 kGE, 6.17 kGE / PE).

## 3. Bit-exact check and energy (GLS tt SDF 2.5 ns, PT PX tt)

| point | weights | RTL (Verilator) | GLS SDF: rows checked / bad, timing violations | array mW | array pJ / block-op | pJ / dense-eq. MAC | + weight-input reg delta pJ / block-op | PE: clock+regs / dot / acc uW | zero-delay GLS: array mW, SDF / zd |
|---|---|---|---|---|---|---|---|---|---|
| qc_L2 | s8kd QC | PASS | PASS: 128 / 0, 0 | 184.83 | 7.22 | 0.1128 | +0.00 | 1102 / 830 / 934 | 123.74, 1.49 |
| qc_L4 | s8kd QC | PASS | PASS: 32 / 0, 0 | 90.73 | 3.54 | 0.0554 | +0.00 | 850 / 332 / 225 | 77.32, 1.17 |
| tern_L2 | s8kd expanded | PASS | PASS: 128 / 0, 0 | 208.73 | 8.15 | 0.1274 | +0.39 | 1092 / 1211 / 928 | 142.67, 1.46 |
| tern_L4 | s8kd expanded | PASS | PASS: 32 / 0, 0 | 99.30 | 3.88 | 0.0606 | +0.37 | 888 / 406 / 244 | 82.37, 1.21 |
| int8_L2 | dense_s0 int8 | PASS | PASS: 128 / 0, 0 | 1365.46 | 53.34 | 0.8334 | +1.37 | 1910 / 14997 / 3660 | 1018.56, 1.34 |
| int8_L4 | dense_s0 int8 | PASS | PASS: 32 / 0, 0 | 1289.08 | 50.35 | 0.7868 | +1.34 | 1751 / 14186 / 3490 | 923.57, 1.40 |
| int8c_L2 | s8kd as int8 | PASS | PASS: 128 / 0, 0 | 580.31 | 22.67 | 0.3542 | +1.01 | 1676 / 4979 / 2059 | 443.11, 1.31 |
| int8c_L4 | s8kd as int8 | PASS | PASS: 32 / 0, 0 | 514.81 | 20.11 | 0.3142 | +1.01 | 1551 / 4265 / 1897 | 344.00, 1.50 |

block-op = one PE processing one 8x8 block (64 MACs) in one cycle; array power = PT u_array (64 PEs + shadow chains) over the 2304-cycle busy window, energy = P x 2.5 ns / 64.  Weight-input reg delta = PT power of the leaf cells outside u_array (input registers) minus the QC run's (the x stream is identical, so this is the wider weight register).  PE split: dot = rotators + trit / 2-term add (QC) or u_dot (TERNARY / INT8), acc = accumulate adder, rest = registers + clock gates.

- L2: array energy vs QC: TERNARY 1.13x, INT8 (dense_s0) 7.39x, INT8c (s8kd) 3.14x
- L4: array energy vs QC: TERNARY 1.09x, INT8 (dense_s0) 14.21x, INT8c (s8kd) 5.67x
## 4. System-level ablation per inference at 400 MHz (MODEL)

Assumptions (all MODELLED unless marked measured):
- A1 (measured, v2 `results/power_v2.md`, SDF SAIF image 0, +dat): everything except the PE array and the weight macros = 79.81 mW x 400.0 us = **31.92 uJ** (act macros, PPU, drain, head, AGU / xbar / seq / host, param + desc macros, wrappers, their leakage); kept for all variants (same schedule: 159982 cycles, 136320 array steps = 8724480 block-ops / inference).
- A2: array = measured pJ / block-op (mean of L2 and L4, incl. the weight-input register delta) x 8724480 block-ops + array leakage (measured, PT) during the 23662 non-array-step cycles.  Check on QC: model 47.14 uJ vs the in-chip measured u_array 53.02 uJ (v2).
- A3 (scenario i, on-chip weight SRAM): built from qa_wgt_4096x80m8 (datatable tt, EMA 000; area incl. ring): read 34.11 pJ / 80 b = **0.4264 pJ / bit**, area 1.0805 um2 / bit, leakage 1.149 mW / macro = 3.505 nW / bit (PT, tt 25 C); energy / area scale linearly with bits (N copies of the macro; capacity = the weight bits exactly).  Weights read every array step as in v2: 80 / 1024 / 4096 b / step.  Capacity: QC 0.218 MB, TERNARY 2.79 MB, INT8 11.16 MB (conv weights; the 5 kB FC is in A1).
- A4 (scenario ii, off-chip DRAM): every weight bit read once per inference at 20 pJ / bit (Horowitz ISSCC 2014, DRAM I/O) or 70 pJ / bit (Malladi ISCA 2012, DDR3).  QC keeps its measured on-chip weight SRAM (v2 weight macros, 7.44 uJ, 6 macros) for the per-step re-reads; TERNARY / INT8 are charged NO on-chip weight buffer: **a lower bound for the dense variants** (each weight block is re-read by every pixel tile, so they need an on-chip buffer of the size in A3 or more DRAM traffic).
- A5: area = v2 layout minus its PE array and weight SRAM (3.726 mm2: act / param / desc macros, PPU, drain, head, control) + the variant's measured array (+ its extra weight-input register area vs QC) + the weight memory of A3 (scenario i) or none / the v2 QC weight macros (scenario ii).  Throughput = min(400 MHz, tt fmax) / 159982 cycles.

| per inference | QC | TERNARY | INT8 |
|---|---|---|---|
| array pJ / block-op (incl. w-reg delta), mean L2 / L4 | 5.38 | 6.40 | 53.20 |
| A1 rest uJ | 31.92 | 31.92 | 31.92 |
| A2 array uJ | 47.14 | 56.10 | 465.55 |
| A2z array uJ from the zero-delay GLS (no glitches; lower bound, sensitivity) | 34.45 | 41.96 | 344.15 |
| A2' array uJ, calibrated: v2 in-chip u_array x A2(v) / A2(QC) (sensitivity) | 53.02 | 63.09 | 523.59 |
| (i) weight SRAM read uJ | 4.65 | 59.52 | 238.07 |
| (i) weight SRAM leakage uJ | 2.45 | 31.30 | 125.20 |
| **(i) total uJ / inference** | **86.2** | **178.8** | **860.7** |
| (i) total with A2' uJ | 92.0 | 185.8 | 918.8 |
| (i) total with A2z uJ | 73.5 | 164.7 | 739.3 |
| (i) vs QC | 1.00x | 2.08x | 9.99x |
| (ii) DRAM 20 pJ / b: DRAM uJ | 34.9 | 446.5 | 1785.9 |
| **(ii) 20 pJ / b total uJ** (dense: lower bound) | **121.4** | **534.5** | **2283.4** |
| (ii) DRAM 70 pJ / b: DRAM uJ | 122.1 | 1562.7 | 6250.8 |
| **(ii) 70 pJ / b total uJ** (dense: lower bound) | **208.6** | **1650.7** | **6748.3** |
| (i) area mm2 (array / weight SRAM / total) | 0.567 / 1.88 / 6.18 | 0.747 / 24.12 / 28.59 | 3.321 / 96.48 / 103.53 |
| (ii) area mm2 (dense: no weight buffer, lower bound) | 6.43 | 4.47 | 7.05 |
| inferences / s (tt) | 2500 | 2500 | 2500 |
| (i) inferences / s / mm2 | 404.7 | 87.4 | 24.2 |
| (ii) inferences / s / mm2 | 389.1 | 559.0 | 354.8 |

## 5. Attribution

Scenario (i), INT8 -> QC saves 774.6 uJ / inference (9.99x):
- compute, INT8 -> TERNARY PE: array 8.30x, 409.5 uJ (52.9 %)
  - of which arithmetic on identical operands (INT8c / TERNARY, s8kd blocks) 3.50x and dense weight statistics (INT8 / INT8c) 2.38x (array + w-reg pJ / block-op, mean L2 / L4)
- compute, TERNARY -> QC PE: array 1.19x, 9.0 uJ (1.2 %)
- weight storage / traffic, int8 -> 2-b trits: weight SRAM 4.00x, 272.5 uJ (35.2 %)
- weight storage / traffic, trits -> QC codes: weight SRAM 12.80x, 83.7 uJ (10.8 %)
- scenario (ii) 20 pJ / b: INT8 -> QC saves >= 2162.0 uJ (18.81x), of which compute 418.4 uJ (19.4 %) and weight traffic (DRAM, minus QC's on-chip SRAM) 1743.6 uJ (80.6 %); TERNARY -> QC >= 413.1 uJ
- scenario (ii) 70 pJ / b: INT8 -> QC saves >= 6539.7 uJ (32.35x), of which compute 418.4 uJ (6.4 %) and weight traffic (DRAM, minus QC's on-chip SRAM) 6121.3 uJ (93.6 %); TERNARY -> QC >= 1442.1 uJ

## 6. Caveats

- Pre-CTS netlists, wire-load model, ideal clock (no clock-tree power; INT8 has the most registers / clock gates), no P&R; tt 25 C leakage.  Same flow and settings for all three variants.
- Activity from two passes of one image (L2, L4: 2304 steps each); the whole-image array energy uses their mean (QC model 47.1 uJ vs 53.0 uJ measured in-chip: row A2' rescales all variants to the in-chip QC number).  The zero-delay rows bound the glitch contribution (SDF / zd ratio per point in section 3).
- No operand isolation / zero-skipping in any PE (v2 has none either).  The activations of these passes are 57 % (L2) and 94 % (L4) zero lanes (ReLU + padding), and the weight register reloads every cycle; an INT8 design with zero-gated multipliers or weight-stationary reuse would cut its array energy, so INT8 compute here is an upper estimate for a different design point, exact for this dataflow.
- INT8 weights are dense_s0's (realistic dense weight statistics) but driven with the s8kd activation stream (the same stream for all variants); INT8c (s8kd blocks as int8) isolates the arithmetic: same operands as QC.
- Accuracy is not part of this ablation (dense_s0 and s8kd are different networks); every variant runs the same 159982-cycle schedule.
- Weight memory: linear per-bit model of one compiled 4096x80 macro (larger / wider macros, periphery sharing, low-leakage or power-gated arrays would lower the dense variants' cost); scenario (ii) is a lower bound for TERNARY / INT8 (no on-chip weight buffer, area and energy) and charges QC its measured on-chip SRAM.
- fmax: all variants close 3.3 ns (synthesis target); the 2.0 ns probe is one extra synthesis per variant, not a sweep.  At 400 MHz (tt) every variant has margin (tt fmax at 3.3 ns >= 466 MHz), so throughput is equal.

## 7. Kb = 2 (v3 array geometry: two 8x8 blocks per PE per cycle)

Same method as sections 1-6, on the v3 array: `QAB_KB=2 qc18acc/ablation/run.sh vec | rtl | start syn | sdf | gls | power | fetch | report` (`vectors3.py`, `rtl/qab3.f`, `report3.py`); host work dirs `/tmp/ckp908/qc18acc/abl3`; summaries `results/ablation_kb2/`.  Labels: **[S]** synthesis estimate (DC / PT, WLM, pre-CTS), **[M]** measured in simulation (Verilator / VCS GLS), **[P]** PT PX power of the synthesised netlist with the GLS SAIF, **[Mo]** model.

### 7.1 Variants

| | QC (v3, unchanged) | TERNARY | INT8 |
|---|---|---|---|
| PE RTL | `hw3/rtl/qa_pe.sv` (4 rotators, fused trits + 4 terms + accumulate, `qa_pe_acc4`) | `ablation/rtl/qab3_pe.sv` V=1: 16 trit-selects + accumulate as ONE sum per lane | V=2: 16 signed 8x8 products + accumulate as ONE sum per lane |
| weight bits / PE-cycle (per column, 2 blocks) | 20 | 256 (2 x 64 trits x 2 b) | 1024 (2 x 64 x int8) |
| weight bits into the array / cycle | 160 | 2048 | 8192 |
| x bits into the array / cycle | 1024 | 1024 | 1024 |
| accumulator | 20 b | 21 b | 32 b |

As v3 does for QC, the TERNARY / INT8 PEs at Kb = 2 compute the whole lane update (16 terms + accumulator) in one combinational sum (one CSA tree for DC; at Kb = 1 they had a separate u_dot and u_acc, as the v2 QC PE).  Everything else as v3: 8 x 8 PEs, rows = 8 output pixels with a 128-b pair word (even / odd input group), output-stationary accumulators, shadow capture / chain, the input pipeline register (`rtl/qab3_top.sv`).

Stream (`vectors3.py`): s8kd_s0 test image 0, the REAL v3 array inputs (v3 golden model `compile3` up to the pass, then `compile3.golden.gather_window`: v3 tap order kh, pair j, kw; even block = v2 tap (kh, kw, 2j), odd = (kh, kw, 2j + 1)).  Same layers and tiles as Kb = 1, i.e. the same 8x8 block-ops in half the steps (1152 steps per point); golden check: QC sums == the v3 golden pass accumulators and == the Kb = 1 sums:
- L2 = blocks.3.c1 (layer 2, S = 72 pair steps / tile, 16 tiles): S 72 tiles 16 steps 1152 x_zero 0.570 x_mean 2.47 qc_zero_coef 0.7715 int8_zero 0.0164 int8_mean_abs 21.40 max_acc qc 536 int8 42339 golden_check PASS
- L4 = blocks.7.c1 (layer 4, S = 288, 4 tiles): S 288 tiles 4 steps 1152 x_zero 0.940 x_mean 0.28 qc_zero_coef 0.7611 int8_zero 0.0149 int8_mean_abs 21.95 max_acc qc 359 int8 49560 golden_check PASS

### 7.2 Area and timing (standalone, DC 3.3 ns ss) [S]

| | QC | TERNARY | INT8 |
|---|---|---|---|
| array (u_array) kGE, Kb = 2 | 514.3 | 818.8 | 3830.5 |
| array kGE, Kb = 1 (section 2) | 393.7 | 513.1 | 2281.2 |
| Kb = 2 / Kb = 1 array area | 1.31x | 1.60x | 1.68x |
| one PE (mean of 64) kGE | 8.00 | 12.76 | 59.50 |
| array mm2 | 0.741 | 1.179 | 5.516 |
| input pipeline registers (x + weights + control) kGE | 5.8 | 17.1 | 49.8 |
| array vs QC | 1.00x | 1.59x | 7.45x |
| fmax ss MHz (WNS ns) | 303.3 (+0.003) | 303.2 (+0.002) | 303.2 (+0.001) |
| fmax tt MHz (WNS ns) | 469.0 (+1.168) | 472.5 (+1.183) | 467.9 (+1.163) |
| fmax ff MHz (WNS ns) | 670.7 (+1.809) | 673.9 (+1.816) | 665.7 (+1.798) |

Worst ss paths: QC `u_wrap/w_reg_67_/CP -> u_wrap/g_qc_u_array/g_col_3__g_row_2__u_pe/sh_out_reg_19_/D`; TERNARY `u_wrap/x_reg_369_/CP -> u_wrap/g_d_u_array/g_col_5__g_row_2__u_pe/sh_out_reg_104_/D`; INT8 `u_wrap/w_reg_499_/CP -> u_wrap/g_d_u_array/g_col_0__g_row_2__u_pe/sh_out_reg_243_/D`.  v3 in-chip QC array: 0.733 mm2 (509.0 kGE).

### 7.3 Bit-exact check and energy (GLS tt SDF 2.5 ns, PT PX tt) [M] [P]

| point | weights | RTL (Verilator) | GLS SDF: rows checked / bad, timing violations | array mW | array pJ / block-op | pJ / dense-eq. MAC | + weight-input reg delta pJ / block-op | per block-op: PE regs + clock / PE datapath / shadow chain + array glue pJ | zero-delay GLS: array mW, SDF / zd |
|---|---|---|---|---|---|---|---|---|---|
| qc_L2 | s8kd QC | PASS | PASS: 128 / 0, 0 | 229.86 | 4.49 | 0.0701 | +0.00 | 1.51 / 2.93 / 0.06 | 158.57, 1.45 |
| qc_L4 | s8kd QC | PASS | PASS: 32 / 0, 0 | 159.15 | 3.11 | 0.0486 | +0.00 | 1.16 / 1.92 / 0.03 | 122.60, 1.30 |
| tern_L2 | s8kd expanded | PASS | PASS: 128 / 0, 0 | 300.26 | 5.86 | 0.0916 | +0.41 | 1.48 / 4.33 / 0.05 | 201.20, 1.49 |
| tern_L4 | s8kd expanded | PASS | PASS: 32 / 0, 0 | 126.86 | 2.48 | 0.0387 | +0.38 | 1.14 / 1.32 / 0.01 | 102.91, 1.23 |
| int8_L2 | dense_s0 int8 | PASS | PASS: 128 / 0, 0 | 2284.24 | 44.61 | 0.6971 | +1.71 | 2.53 / 41.17 / 0.91 | 1671.02, 1.37 |
| int8_L4 | dense_s0 int8 | PASS | PASS: 32 / 0, 0 | 2113.12 | 41.27 | 0.6449 | +1.68 | 2.26 / 38.18 / 0.84 | 1577.66, 1.34 |
| int8c_L2 | s8kd as int8 | PASS | PASS: 128 / 0, 0 | 894.65 | 17.47 | 0.2730 | +1.13 | 2.35 / 14.70 / 0.43 | 656.22, 1.36 |
| int8c_L4 | s8kd as int8 | PASS | PASS: 32 / 0, 0 | 773.16 | 15.10 | 0.2359 | +1.13 | 2.09 / 12.62 / 0.39 | 557.48, 1.39 |

block-op = one 8x8 block (64 MACs) on one PE; a Kb = 2 PE does two per cycle, so energy / block-op = P x 2.5 ns / 64 / 2 (1152 busy cycles per point).  Datapath = rotators + fused sum (QC), the fused u_acc (TERNARY / INT8); regs + clock = accumulator / shadow registers, their clock gates and clock pins.

- L2: array energy vs QC: TERNARY 1.31x (Kb = 1: 1.13x), INT8 (dense_s0) 9.94x (7.39x), INT8c (s8kd) 3.89x (3.14x)
- L4: array energy vs QC: TERNARY 0.80x (Kb = 1: 1.09x), INT8 (dense_s0) 13.28x (14.21x), INT8c (s8kd) 4.86x (5.67x)

**Kb = 1 -> Kb = 2 per block-op (mean of L2 / L4, pJ) [P]:**

| variant | Kb | array | PE regs + clock | PE datapath | shadow chain + glue | w-reg delta |
|---|---|---|---|---|---|---|
| QC | 1 | 5.38 | 2.44 | 2.90 | 0.04 | +0.00 |
| QC | 2 | 3.80 | 1.33 | 2.42 | 0.04 | +0.00 |
| TERNARY | 1 | 6.02 | 2.48 | 3.49 | 0.05 | +0.38 |
| TERNARY | 2 | 4.17 | 1.31 | 2.83 | 0.03 | +0.40 |
| INT8 | 1 | 51.85 | 4.58 | 45.42 | 1.85 | +1.36 |
| INT8 | 2 | 42.94 | 2.39 | 39.68 | 0.87 | +1.70 |
| INT8c | 1 | 21.39 | 4.03 | 16.50 | 0.85 | +1.01 |
| INT8c | 2 | 16.29 | 2.22 | 13.66 | 0.41 | +1.13 |

### 7.4 System-level ablation per inference at 400 MHz, v3 (MODEL) [Mo]

Assumptions (all MODELLED unless marked measured), as section 4 with the v3 numbers:
- B1 (measured [P] + [Mo] macros, v3 `results/power_v3`, SDF SAIF image 0, +dat): everything except the PE array and the weight macros = 127.99 mW x 203.6 us = **26.06 uJ**; kept for all variants (same v3 schedule: 81438 cycles, 68736 array steps = 8798208 block-op slots / inference; the stem's odd blocks are zero words, counted as block-ops here).
- B2: array = measured pJ / block-op (mean of L2 and L4, incl. the weight-input register delta) x 8798208 block-ops + array leakage during the 12702 non-array-step cycles.  Check on QC: model 33.54 uJ vs the in-chip measured v3 u_array 36.27 uJ.
- B3 (scenario i, on-chip weight SRAM): qa_wgt_4096x80m8 per-bit model of section 4 (0.4264 pJ / bit read, 1.0805 um2 / bit, 3.505 nW / bit), capacity = the weight bits, read every array step: 160 / 2048 / 8192 b / step (two blocks per column).  Check on QC: 4.69 uJ vs the v3 datatable 4.71 uJ.
- B4 (scenario ii, off-chip DRAM): every weight bit read once per inference at 20 / 70 pJ / bit; QC keeps the v3 weight macros (6.13 uJ incl. leakage, measured [P] + [Mo]); TERNARY / INT8 no on-chip weight buffer (lower bound).
- B5: area = v3 layout minus its PE array and weight SRAM (3.649 mm2) + the variant's array (+ extra weight-input register area vs QC) + the weight memory of B3 (scenario i) or none / the v3 QC weight macros (scenario ii).  Throughput = min(400 MHz, tt fmax) / 81438 cycles.
- B6 (storage row only): 2:8-sparse ternary weights stored at 64 b per 8x8 block (1 b / weight) vs 10 b per block for QC codes and 128 b for dense 2-b trits; no PE is modelled for it (its compute would need a sparse-ternary PE), only weight SRAM read (1024 b / step), leakage, area and DRAM.

| per inference | QC | TERNARY | INT8 |
|---|---|---|---|
| array pJ / block-op (incl. w-reg delta), mean L2 / L4 [P] | 3.80 | 4.57 | 44.64 |
| B1 rest uJ | 26.06 | 26.06 | 26.06 |
| B2 array uJ | 33.54 | 40.42 | 393.87 |
| B2z array uJ from the zero-delay GLS (no glitches; lower bound) | 24.28 | 29.85 | 295.18 |
| B2' array uJ, calibrated to the v3 in-chip u_array (sensitivity) | 36.27 | 43.70 | 425.85 |
| (i) weight SRAM read uJ | 4.69 | 60.02 | 240.09 |
| (i) weight SRAM leakage uJ | 1.24 | 15.93 | 63.73 |
| **(i) on-chip system total uJ / inference** | **65.5** | **142.4** | **723.7** |
| (i) total with B2' uJ | 68.3 | 145.7 | 755.7 |
| (i) total with B2z uJ | 56.3 | 131.9 | 625.1 |
| (i) vs QC | 1.00x | 2.17x | 11.04x |
| (ii) DRAM 20 pJ / b: DRAM uJ | 34.9 | 446.5 | 1785.9 |
| **(ii) 20 pJ / b total uJ** (dense: lower bound) | **100.6** | **513.0** | **2205.9** |
| (ii) DRAM 70 pJ / b: DRAM uJ | 122.1 | 1562.7 | 6250.8 |
| **(ii) 70 pJ / b total uJ** (dense: lower bound) | **187.8** | **1629.2** | **6670.7** |
| **(i) area mm2** (array / weight SRAM / total) | 0.741 / 1.88 / **6.27** | 1.195 / 24.12 / **28.97** | 5.579 / 96.48 / **105.71** |
| (ii) area mm2 (dense: no weight buffer, lower bound) | 6.52 | 4.84 | 9.23 |
| inferences / s (tt, <= 400 MHz) | 4912 | 4912 | 4912 |
| **(i) inferences / s / mm2** | **782.8** | **169.6** | **46.5** |
| (ii) inferences / s / mm2 | 753.2 | 1013.8 | 532.2 |

**Weight storage only (B3 / B4 / B6) [Mo]:**

| per inference | QC codes (10 b / block) | 2:8-sparse ternary (64 b / block) | dense ternary (128 b / block) | INT8 (512 b / block) |
|---|---|---|---|---|
| weight capacity MB | 0.218 | 1.395 | 2.791 | 11.162 |
| vs QC | 1.00x | 6.40x | 12.80x | 51.20x |
| (i) SRAM read + leakage uJ | 5.93 | 37.98 | 75.95 | 303.82 |
| (i) SRAM area mm2 | 1.88 | 12.06 | 24.12 | 96.48 |
| (ii) DRAM 20 pJ / b uJ | 34.9 | 223.2 | 446.5 | 1785.9 |
| (ii) DRAM 70 pJ / b uJ | 122.1 | 781.3 | 1562.7 | 6250.8 |

### 7.5 Attribution (Kb = 2) [Mo]

Scenario (i), INT8 -> QC saves 658.2 uJ / inference (11.04x):
- compute, INT8 -> TERNARY PE: array 9.74x, 353.5 uJ (53.7 %)
  - of which arithmetic on identical operands (INT8c / TERNARY) 3.81x and dense weight statistics (INT8 / INT8c) 2.56x (array + w-reg pJ / block-op, mean L2 / L4)
- compute, TERNARY -> QC PE: array 1.21x, 6.9 uJ (1.0 %)
- weight storage / traffic, int8 -> 2-b trits: weight SRAM 4.00x, 227.9 uJ (34.6 %)
- weight storage / traffic, trits -> QC codes: weight SRAM 12.80x, 70.0 uJ (10.6 %)
- storage only, 2:8-sparse ternary -> QC codes: weight SRAM 6.40x, 32.0 uJ; DRAM 6.4x the bits (188.4 / 659.3 uJ more at 20 / 70 pJ / b)
- scenario (ii) 20 pJ / b: INT8 -> QC saves >= 2105.3 uJ (21.92x), of which compute 360.3 uJ (17.1 %) and weight traffic 1744.9 uJ (82.9 %); TERNARY -> QC >= 412.4 uJ
- scenario (ii) 70 pJ / b: INT8 -> QC saves >= 6482.9 uJ (35.52x), of which compute 360.3 uJ (5.6 %) and weight traffic 6122.6 uJ (94.4 %); TERNARY -> QC >= 1441.4 uJ

Key numbers (Kb = 2):

| | QC | TERNARY | INT8 |
|---|---|---|---|
| array kGE [S] | 514.3 | 818.8 | 3830.5 |
| pJ / block-op (array + w-reg, mean L2 / L4) [P] | 3.80 | 4.57 | 44.64 |
| on-chip system uJ / inference (i) [Mo] | 65.5 | 142.4 | 723.7 |
| mm2 (i) [Mo] | 6.27 | 28.97 | 105.71 |
| inferences / s / mm2 (i) [Mo] | 782.8 | 169.6 | 46.5 |
| DRAM uJ at 20 / 70 pJ / b [Mo] | 34.9 / 122.1 | 446.5 / 1562.7 | 1785.9 / 6250.8 |

### 7.6 Why the QC-vs-TERNARY compute gap changes from Kb = 1 to Kb = 2

TERNARY / QC array energy per block-op (incl. the weight-register delta, mean L2 / L4): Kb = 1 1.19x, Kb = 2 1.20x.  The mean barely moves, but per layer it does: L2 1.13x -> 1.31x (gap widens), L4 1.09x -> 0.80x (TERNARY becomes cheaper than QC).  Three mechanisms, measured on the PE split of 7.3 (pJ per block-op) and on the operand toggles of the streams (`operand_toggles.py`, per PE-cycle = 2 blocks):
1. **Registers + clock amortise over Kb, equally for both.**  One set of 8 accumulators + 8 shadow registers and their clock gates serves Kb blocks per cycle: QC 2.76 / 2.12 -> 1.51 / 1.16, TERNARY 2.73 / 2.22 -> 1.48 / 1.14 pJ (L2 / L4).  Being the same for QC and TERNARY (20- vs 21-b accumulators), this part never contributes to the gap; halving it makes the datapath difference a larger share of the total, which by itself widens the ratio.
2. **The datapath per block gets cheaper with the fused Kb = 2 sum for both** (one carry-save tree incl. the accumulator, one carry-propagate add per 2 blocks instead of a block add + a 20-b accumulate add per block): L2 datapath QC 4.41 -> 2.93, TERNARY 5.35 -> 4.33 pJ.  QC saves more per block (x1.51 vs x1.23): its per-block work is 2 operands per lane, so the carry-propagate adds it sheds are a large part of it; a ternary block brings 8 operands per lane and its compressor tree, which does not shrink, dominates.  With items 1 and 2 the L2 gap widens.
3. **The v3 QC negate encoding toggles with the weight sign, independent of the data.**  qa_pe_acc4 forms a negative term as (x XOR 1...1) + carry-in, so a 20-b operand flips all its bits whenever the sign of its trit changes from one step to the next, even for x = 0; the v2 QC PE (and the TERNARY PEs) use the value form (+x / -x / 0), which stays 0 for x = 0.  Operand toggles per PE-cycle, QC XOR form / QC value form / TERNARY values: L2 282 / 200 / 252, L4 245 / 41 / 44 (x lanes zero: L2 57 %, L4 94 %; 61 % of the L4 terms are negative).  On the zero-heavy L4 stream the QC datapath therefore costs MORE per block at Kb = 2 than at Kb = 1 (1.39 -> 1.92 pJ; the zero-delay runs show the same, so it is functional toggling, not glitches), while TERNARY drops (1.63 -> 1.32): the L4 gap inverts.
Net: the PE-level QC-vs-TERNARY compute gap stays small at Kb = 2 (about the Kb = 1 value on the mean of the two layers) because items 1-2 (widening) and item 3 (a QC-specific, data-independent cost that grows with the zero share) cancel on these two passes.  A value-form negate (or gating the XOR with e AND x != 0) in qa_pe_acc4 would remove item 3 (not evaluated here).  The system-level QC advantage remains weight storage / traffic (7.5): 160 vs 2048 b per array step.

### 7.7 Caveats (Kb = 2)

- As section 6 (pre-CTS, WLM, ideal clock, tt 25 C; activity of two passes of image 0; no operand isolation / zero skipping).  The B1 rest is the v3 chip's own (measured), so the Kb = 2 totals are not comparable 1:1 with the Kb = 1 totals of section 4 (v2 rest, 159 982 cycles), only variant-to-variant.
- The TERNARY / INT8 PEs got the same fused-sum treatment as the v3 QC PE (one adder tree incl. the accumulator); at Kb = 1 all three PEs had a separate block sum and accumulate adder.  Kb = 1 -> Kb = 2 therefore changes both the block count per cycle and the adder structure, for all three variants alike.
- Weight memory: linear per-bit model of the 4096x80 macro (section 6); the 2:8-sparse ternary row is storage / DRAM only (no sparse PE, no index-decode logic).
- fmax: one synthesis at 3.3 ns per variant, no 2.0 ns probe at Kb = 2.
