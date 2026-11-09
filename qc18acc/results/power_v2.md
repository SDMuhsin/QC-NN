# QC18-ACC v2: macro clock gating + kw sliding window (vs v1)

v1 = git tag `qc18acc-v1`, netlist `qa_w3.3`, [power.md](power.md) (unchanged).  v2 = this tree, netlist `qa2_w3.3`
(same flow: DC W-2024.09, tcbn65gplus, WLM WireAreaLowkCon enclosed, 3.3 ns at ss; PT pre-CTS ideal clock).
Workload: one full inference of s8kd, test image 0, START..DONE = 159 982 cycles (v1 and v2).

## 1. Changes

1. **Macro clock gating** (`hw/tech/qa_sram_tech.sv`): every macro CLK (24 act, 6 weight, 2 param, 1 descriptor)
   comes from a library integrated clock gate `CKLNQD2` (TE = 0, E = access request `ce`, the macro's ~CEN); CEN
   is still driven.  Behavioural `qa_sram` and the hold-register logic (ungated `clk`) unchanged.  DC: `size_only`.
2. **kw sliding window** (ARCH.md "kw window"): tap order per tile kh, cb, kw (stride-2 3x3: kw 0, 2, 1, since kw 0
   and 2 read the same odd-x phase plane at base + 1 — verified against `layout.tap_offset`); compiler weight-word
   order, golden model (literal path through `golden.gather_window`), Appendix, RTL AGU (`have`/`held`/`rd` slot
   state) and xbar (8 x 64-b raw window in S3, shift + per-slot bank load, registered lane mask ANDed at the array
   input).  Only `rd = lane & ~held` banks are read: one bank per shift step (two at the row wrap of 4-wide maps),
   the valid lanes on the first tap of a run; padding slots are never read and never reach a PE.  Perf counter
   `CSR_ACT_RD` (0x0d) = array act-bank reads.  Cycle model unchanged (cycles identical to v1).
3. **PE sub-instances** (for section 5): `qa_pe_rot` x 2, `qa_pe_tadd` (trit + 2-term add, 10 b), `qa_pe_acc`
   (accumulate add, 20 b), registers in `qa_pe`.  Same function; v1 had one 3-input add per lane (see 5.2: the
   split costs ~+4 % PE power through glitches).

## 2. Verification (bit-exact chain)

| level | result |
|---|---|
| compiler unit tests (`test_compile`, incl. new `test_window`: tap order is a permutation, structural shift rule == index rule on every ResNet-18 + mini pass, reads <= v1, window gather == direct gather on garbage-filled buffers) | ALL PASS |
| golden == IntNet (`main --n 200 --literal 4`) | BIT-EXACT PASS: 200 images, logits + pooled + all 20 maps; literal path (through the window model) PASS on 4 |
| RTL unit (iverilog `run_unit.sh mini`: tb_pe, tb_ppu, mini program) | PASS; mini act reads 8 496 = model |
| VCS RTL, images 0..3, plain RTL | RESULT PASS, all logits + 20 maps per image; 159 982 cycles; act reads 409 572 = model |
| VCS RTL, images 0..3, `QC_TECH=1` (macro models + CKLNQD cell models) | RESULT PASS |
| GLS zero delay, `qa2_w3.3`, image 0 | RESULT PASS, 22 cycle counters = RTL |
| GLS tt SDF (ideal clock incl. the 33 macro ICGs, timing checks on), 2.5 ns, image 0, SAIF | RESULT PASS, 22 counters = RTL, 0 timing violations |

## 3. Implementation (`impl/results/qa2_w3.3`)

Area 6.430 mm2 (v1 6.433), logic 612.4 kGE (614.9), PE 6.17 kGE (6.26; split adders slightly smaller), xbar
10.3 kGE (8.0: the shift / load mux of the 512 window bits; the lane mask moved after the register).  fmax ss 303.2 / tt 463.3 / ff 658.0 MHz
(v1 303.2 / 462.9 / 666.2); ss critical path unchanged (weight macro -> head FC dot), the v2 PE path
(`u_xbar/s3_lane` -> mask -> PE -> `sh_out`) closes at 3.3 ns ss (DC WNS 0.000).

Clock gates: DC keeps the 33 `CKLNQD2` (size_only; DC's `report_clock_gating` counts only register gates, 1 197
tool-inserted).  PT (all three corners): qa_clk reaches 33 / 33 macro CLK pins through the ICGs; the ICG enable
checks are reported by `report_clock_gating_check` (33 `u_cg` entries, library ICG, "High P L") and as E-pin
setup / hold: slack ss +0.311 / +0.410, tt +1.390 / +0.236, ff +1.970 / +0.139 ns; `check_timing -verbose`: 0
warnings.  GLS SDF: the CKLNQD IOPATHs are zeroed as the ideal clock (1 230 CKLNQD = 1 197 + 33).

## 4. Power, v1 vs v2 (tt, 400 MHz, SDF SAIF of the full image, +dat = macro access energy from the datatables)

`power.sh -o power_v2 -e qa2_w3.3 sdf|zd`, `compare.py sdf 2.5` (macro_dat.py now counts per cycle: accesses =
1 - P(CEN=1), deselected clocks = CLK edges - accesses; reproduces the v1 numbers to 6 digits).

| quantity (sdf SAIF, 2.5 ns = 400 MHz, tt, +dat) | v1 | v2 | v2 - v1 |
|---|---|---|---|
| total power mW (+dat) | 308.4 | 231.0 | -77.4 |
| total power mW (PT only) | 198.6 | 203.9 | 5.4 |
| energy uJ / inference (+dat) | 123.3 | 92.4 | -30.9 |
| pJ / dense-equivalent MAC | 0.2220 | 0.1663 | -0.0557 |
| &nbsp;&nbsp;PE array (u_array) mW | 127.3 | 132.6 | 5.3 |
| &nbsp;&nbsp;PPU (u_ppu) mW | 34.8 | 33.9 | -0.9 |
| &nbsp;&nbsp;drain (u_drain) mW | 2.0 | 2.0 | -0.0 |
| &nbsp;&nbsp;head (u_head) mW | 0.8 | 0.7 | -0.0 |
| &nbsp;&nbsp;AGU + xbar + seq + host + top glue mW | 7.0 | 7.6 | 0.6 |
| &nbsp;&nbsp;act buffer logic (hold regs, port muxes) mW | 1.7 | 1.4 | -0.2 |
| &nbsp;&nbsp;weight / param / desc wrapper logic mW | 0.6 | 0.5 | -0.1 |
| &nbsp;&nbsp;activation macros (24 x 1024x64) mW | 84.7 | 31.1 | -53.7 |
| &nbsp;&nbsp;weight macros (6 x 4096x80) mW | 39.1 | 18.6 | -20.5 |
| &nbsp;&nbsp;param macros (2 x 4096x72) mW | 10.0 | 2.5 | -7.5 |
| &nbsp;&nbsp;descriptor macro (256x32) mW | 0.4 | 0.1 | -0.3 |
| &nbsp;&nbsp;of which macro clock gates (33 CKLNQD, in the wrapper logic rows) mW | 0.0 | 0.2 | 0.2 |
| leakage mW | 21.8 | 22.0 | 0.2 |
| act macros: reads / cycle (all instances) | 6.160 | 2.830 | -3.330 |
| act macros: clock edges / cycle per instance | 1.000 | 0.139 | -0.861 |
| weight macros: reads / cycle (all instances) | 0.856 | 0.856 | 0.000 |
| weight macros: clock edges / cycle per instance | 1.000 | 0.143 | -0.857 |
| param macros: reads / cycle (all instances) | 0.030 | 0.030 | -0.000 |
| param macros: clock edges / cycle per instance | 1.000 | 0.015 | -0.985 |
| desc macros: reads / cycle (all instances) | 0.001 | 0.001 | 0.000 |
| desc macros: clock edges / cycle per instance | 1.000 | 0.001 | -0.999 |
| macro deselected-clock power mW (all macros) | 60.5 | 0.0 | -60.5 |
| act macro read power mW | 39.8 | 18.3 | -21.5 |
| array act-bank reads / image (RTL counter; v1 = model) | 946644 | 409572 | -537072 |
| array act-bank reads / cycle | 5.917 | 2.560 | -3.357 |
| area mm2 (total) | 6.433 | 6.430 | -0.003 |
| logic mm2 | 0.885 | 0.882 | -0.003 |
| logic kGE | 614.9 | 612.4 | -2.5 |
| PE array kGE | 401.5 | 396.4 | -5.1 |
| one PE kGE | 6.26 | 6.17 | -0.09 |
| fmax ss MHz | 303.2 | 303.2 | 0.0 |
| fmax tt MHz | 462.9 | 463.3 | 0.4 |
| fmax ff MHz | 666.2 | 658.0 | -8.2 |

zd SAIF (2.5 ns): v1 264.0 -> v2 186.3 mW (+dat), 105.6 -> 74.5 uJ; glitch factor SDF / zd 1.332 (v1 1.343).
The v2 act macro reads / cycle are 2.830 (SDF) vs 2.803 (zd): CEN glitches inside the cycle (combinational from
the slot mask) shorten the CEN = 1 time slightly; the ICG samples E at the edge, so the gated CLK edges are not
affected (array reads by the RTL counter: 2.560 / cycle; the rest are PPU residual and head reads, 0.243 / cycle
in both versions).

**Where the 77.4 mW went:** deselected macro clocks 60.5 -> 0.0 mW (act 32.1, weight 20.5, param 7.5, desc 0.3;
the 33 ICGs cost 0.2 mW), act macro reads 39.8 -> 18.3 mW (x0.433 array reads); PE array +5.3 mW (section 5.2),
xbar/AGU +0.6 mW.  v2: 231.0 mW = **92.4 uJ / inference** (x0.75), 0.166 pJ / dense-equivalent MAC.

Full v2 tables (`python3 qc18acc/power/energy.py qc18acc/results/power_v2`):

| SAIF | clock | PT total mW | int / switch / leak mW | +dat total mW | leakage share (+dat) | uJ / inference PT / +dat | pJ / dense MAC (+dat) | pJ / QC add (+dat) |
|---|---|---|---|---|---|---|---|---|
| sdf | 2.5 ns (400 MHz) | 203.94 | 128.50 / 53.46 / 21.98 | 230.98 | 10.8 % (9.5 %) | 81.57 / 92.38 | 0.1663 | 0.726 |
| zd | 2.5 ns (400 MHz) | 158.56 | 94.96 / 41.62 / 21.98 | 186.30 | 13.9 % (11.8 %) | 63.42 / 74.51 | 0.1342 | 0.585 |

sdf SAIF, 2.5 ns: blocks (PT total; +dat: macro internal power from the datatable model)

| block | PT mW | % PT | +dat mW | % +dat | leakage mW |
|---|---|---|---|---|---|
| PE array (u_array) | 132.57 | 65.0 | 132.57 | 57.4 | 3.25 |
| PPU (u_ppu) | 33.88 | 16.6 | 33.88 | 14.7 | 0.77 |
| drain (u_drain) | 1.98 | 1.0 | 1.98 | 0.9 | 0.23 |
| head (u_head) | 0.75 | 0.4 | 0.75 | 0.3 | 0.17 |
| AGU + xbar + seq + host + top glue | 7.59 | 3.7 | 7.59 | 3.3 | 0.19 |
| act buffer logic (hold regs, port muxes) | 1.45 | 0.7 | 1.45 | 0.6 | 0.15 |
| weight / param / desc wrapper logic | 0.53 | 0.3 | 0.53 | 0.2 | 0.06 |
| activation macros (24 x 1024x64) | 13.21 | 6.5 | 31.07 | 13.5 | 8.07 |
| weight macros (6 x 4096x80) | 9.76 | 4.8 | 18.61 | 8.1 | 6.89 |
| param macros (2 x 4096x72) | 2.18 | 1.1 | 2.52 | 1.1 | 2.14 |
| descriptor macro (256x32) | 0.05 | 0.0 | 0.05 | 0.0 | 0.05 |
| **total** | 203.94 | 100 | 230.98 | 100 | 21.98 |

PT power groups (cross-cutting; mW total): clock_network 61.20 (ICGs + register clock pins + clock nets, ideal clock, no CTS buffers; internal 51.50, switching 9.65), register 14.60, combinational 102.90, memory 25.20.

macro datatable model (per cycle, all instances of a type):

| macro | reads / cycle | writes / cycle | deselected clocks / cycle | E read / write / desel pJ | P read / write / desel mW |
|---|---|---|---|---|---|
| qa_act_1024x64m8 (x24) | 2.830 | 0.516 | 0.000 | 16.1 / 22.8 / 4.64 | 18.27 / 4.71 / 0.00 |
| qa_dsc_256x32m2 (x1) | 0.001 | 0.000 | 0.000 | 7.3 / 10.4 / 0.86 | 0.00 / 0.00 / 0.00 |
| qa_wgt_4096x80m8 (x6) | 0.856 | 0.000 | 0.000 | 34.1 / 37.9 / 9.95 | 11.68 / 0.00 / 0.00 |
| qa_par_4096x72m8 (x2) | 0.030 | 0.000 | 0.000 | 31.3 / 34.7 / 9.53 | 0.38 / 0.00 / 0.00 |

## 5. PE-internal power (v2, SDF SAIF, 2.5 ns), per PE averaged over the 64 PEs

**Method** (`power/pe_power.tcl`, run by `power.sh -e`): same PT session setup as `pt_power.tcl` (tt, WLM, ideal
clock, SDF SAIF of image 0).  Every leaf cell under each `u_array/*u_pe` is assigned to a group by hierarchy (the v2
RTL sub-instances) or register name; PT per-cell power = internal + switching of the cell's output nets + leakage.
The register clock-pin internal power is taken per register from `report_power -cell_power -groups
clock_network` and moved from the register groups to "clock"; the DC clock gates (`clk_gate_*`, CKLNQD, with the
gated-clock nets) are in "clock".  The groups sum exactly to the PE hierarchy power (2046.9 uW / PE; x64 = 131.0
mW of the 132.6 mW PE array; the rest is the array-level input nets).  Not separable: the 2-term add and the trit
negate are one adder in `u_tadd` (negation folded into the adder carry-in by synthesis).

| group | internal uW | switching uW | leakage uW | total uW | % of PE | x64 mW |
|---|---|---|---|---|---|---|
| rotators (u_rot1 + u_rot2, mux cells) | 43.0 | 91.5 | 7.95 | 142.4 | 7.0 | 9.12 |
| trit / negate + 2-term adders (u_tadd) | 257.6 | 154.4 | 13.67 | 425.7 | 20.8 | 27.24 |
| accumulator adders (u_acc) | 374.4 | 166.0 | 13.61 | 553.9 | 27.1 | 35.45 |
| accumulator registers (160 b, data part) | 117.5 | 4.6 | 5.79 | 127.9 | 6.2 | 8.18 |
| shadow registers (160 b, data part) | 12.7 | 1.2 | 6.19 | 20.1 | 1.0 | 1.29 |
| PE top-level logic: shadow capture / shift-in (drain) muxes | 20.3 | 45.8 | 2.84 | 68.9 | 3.4 | 4.41 |
| clock: DC clock gates + register clock pins | 593.7 | 114.1 | 0.28 | 708.1 | 34.6 | 45.32 |

Per PE: 160 accumulator + 160 shadow flops; the "clock" group is 0.594 mW internal (ICGs + the 320 clock pins,
whose clock is enabled during ~85 % of the cycles for the accumulators) + 0.114 mW gated-clock net switching.
zd SAIF (same netlist, no glitches): rotators 139.6, tadd 337.1, accadd 185.7, accreg 38.5, shreg 18.1, top 62.0,
clock 708.0 uW (1 489 uW / PE): the accumulate adder (x2.98) and the accumulator register data pins (x3.3) carry
most of the PE glitch power (PE glitch factor 1.37).

### 5.2 v1 (flat PE) with the same method (`results/power/sdf_2.5ns_pe.txt`)

| group | v1 uW / PE | v2 uW / PE |
|---|---|---|
| clock (clock gates + register clock pins) | 708.1 | 708.1 |
| accumulator registers (data part) | 108.8 | 127.9 |
| shadow registers (data part) | 20.1 | 20.1 |
| all combinational logic (v1: flat; v2: rot + tadd + accadd + top) | 1135.2 | 1190.9 |
| **PE total** | 1972.2 | 2046.9 |

The +74.7 uW / PE (+4.8 mW array) of v2 is the split 2-term + accumulate adder (v1: one 3-input add per lane):
serial carry chains glitch more (comb. +55.7, the accumulator D pins +19.1; in zd the v2 PE is 1 489 uW).  The
kw-inner order also changes the PE input statistics, which this comparison cannot separate from the adder split.  Restoring the fused 3-input form (keeping the hierarchy as one
`trit + add` sub-instance) would recover it; the split was kept so that the breakdown above exists.

## 6. Remaining losses (v2, 231.0 mW)

PE array 132.6 mW (57 %), of which clock 45.3 mW and adders 62.7 mW; PPU 33.9 mW; act macros 31.1 mW (reads 18.3,
writes 4.7, leakage 8.1); weight macros 18.6 mW (reads 11.7 = one 80-b word per busy cycle, leakage 6.9);
leakage total 22.0 mW (9.5 %).

## 7. Low-voltage point (tt 0.8 V)

See [lowv.md](lowv.md): logic-only fmax 309.8 MHz at tt 0.8 V (the kit memory compilers have no 0.8 V corner, macro
paths not part of the claim); at 300 MHz with the same SAIF: 107.1 mW, **57.1 uJ / inference** (macro energies
modelled: datatable x 0.64, leakage x 0.44), leakage share 9.0 %; 1.0 V at the same 300 MHz: 178.7 mW, 95.3 uJ.
