# QC18-ACC array ablation: QC vs TERNARY vs INT8 PE (same array, pipeline, dataflow)

Scripts: `qc18acc/ablation/` (README: qc18acc/README.md, "Array ablation").  Flow as `impl/` (DC W-2024.09, tcbn65gplus, WLM WireAreaLowkCon enclosed, 3.3 ns at ss, `impl/constraints.sdc`; PT ss / tt / ff pre-CTS), GLS VCS with the DC tt SDF (ideal clock, 0.5 ns input delay, timing checks on) at 2.5 ns, PT PX tt 1.0 V 25 C with the synthesis WLM over the SAIF of the PE busy window.  Summaries: `results/ablation/`.

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
