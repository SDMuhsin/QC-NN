# qc18bacc PPU requant lane: area minimisation (qb_lane_n -> qb_lane_s8)

Scope: the requants of the stem, the binary blocks (c2m, scm) and the identity shortcut (idm). They must stay bit-exact to `qc18b/int_bin.py` (requant = `qc18.int8.requant`). The block-6 and pool requants run on qb_lane_w and are not covered here.
Flow: same as micro.md. `qc18bacc/impl/run.sh all <top> 2.0` with DC `compile_ultra -no_autoungroup -gate_clock`, WLM WireAreaLowkCon/enclosed, tt compile, PT tt/ss. Batches were run with `impl/lane_batch.sh` on tau5/usask.
Numbers come from `impl/lane_summary.py`. Raw lines are in `lane_runs.txt`.
RTL: `hw/rtl/qb_lane_s.sv`. It is hierarchical, with one sub-module per function, so `report_area -hierarchy` gives the breakdown.
Every design below meets 500 MHz at tt (PT fmax_tt 500.3-501.8 MHz) unless stated otherwise.

## 1. Breakdown of qb_lane_n (tt, 2.0 ns)

`qb_lane_h` is the same function and the same pipeline as qb_lane_n, written hierarchically. It passes the qb_lane reference with 200k random vectors. Area: 7200.0 um2 (flat qb_lane_n: 7214.0).

| part | um2 | % |
|---|---|---|
| multiplier 16x27 (u_mul, Booth by DC) | 3587.8 | 49.8 |
| round / shift: 6-b barrel over 43 b + increment + 18-b clamp (u_rsh) | 1210.3 | 16.8 |
| adders / saturation / compare: h+r and x>=T (u_hr 219.6), +hr, sat, >T, mode mux (u_s3 402.1) | 621.7 | 8.6 |
| registers, input S0 (x, m, sh, h, r, t, mode, vld: 100 b) | 684.0 | 9.5 |
| registers, datapath pipeline (P 43 b, y2 18 b) | 417.2 | 5.8 |
| registers, carried h+r / T / sh / c / mode / vld (S1 and S2, 76 b of which are h/r/T/sh/c) | 547.2 | 7.6 |
| registers, output (vld, y, b) | 123.1 | 1.7 |
| glue | 8.6 | 0.1 |

All registers together: 1771.5 um2 (24.6 %), 259 flops.
At 4.0 ns the same design is 6441.8 um2 (multiplier 3210.8, shift 925.2), so the 2.0 ns timing costs 11 %.

## 2. Widths (workload.py --lane, GPU 0, val[:2000], E6_s{0,1}; worst-case domains as in item [4]): `lane_widths_E6_s{0,1}.txt`

These are exact interval bounds, not samples. The stem is required to be exact after IntBin's [-32767, 32767] clamp; all other requants are required to be exact unclamped.

| (max over in-scope layers) | E6_s0 | E6_s1 |
|---|---|---|
| input width XW (signed) | 16 (idm: [0, 32767]; stem 14 / 12, c2 <= 11, sc <= 6) | 16 |
| MW, per-channel shift (as item [4]) | 26 | 27 |
| MW, shift COMMON per layer (per-pass) | **34** (stem; without the stem 27) | **28** |
| MW, per-pass shift from a 16-position window | 34 | 28 |
| MW, one network-wide constant shift (no shifter) | 36 (s = 24) | 35 |
| MW, per-channel shift restricted to [17, 24] (3 b) | 29 | 28 |
| MW, per-channel shift restricted to [9, 24] (4 b) | 26 | 27 |
| requant output \|y\| over the domain | 97940 | 129282 (< 2^17: 18 b with no clamp) |
| c2 pass \|y + c2h + rs\| | 129784 | 162004 (19 b) |

- **The stem forces the per-pass MW of E6_s0 to 34.** Its 64 channels span a wide multiplier range: one channel needs s' >= 23 to be exact, and at s' = 23 another channel needs 34 bits.
- **Per-layer common shifts span 7..24.** A per-pass shift therefore still needs a 4-b window, and per-pass is never narrower than per-channel.
- Thresholds: T1 lies in [-6895, 8484], T2 in [-140, 16402], and the c1 accumulator (the mode-1 x) in [-693, 750]. T therefore fits in 16 b with a compiler clamp, and the clamp is exact.

## 3. Variants (tt, 2.0 ns, um2; vs qb_lane_n 7214.0)

| top | change | area | delta | regs | mult / shift+round / add-sat-cmp |
|---|---|---|---|---|---|
| qb_lane_sa | (a) XW 16 / MW 27: step 2 gives no reduction (idm needs 16 b, E6_s1 needs 27 b). T 16 b; shift 4-b window [9, 24]; y truncated to 18 b (no clamp) | 6283.1 | -12.9 % | 243 | 3557 / 438 / 617 |
| qb_lane_sb | (b) per-pass 4-b shift register (not carried), MW 34 | 6891.8 | -4.5 % | 246 | 4096 / 434 / 663 |
| qb_lane_sbk | (b) one constant shift 24, MW 36, no shifter | 6370.6 | -11.7 % | 229 | 4056 / 77 / 663 |
| qb_lane_sb28 | (b) per-pass, MW 28 (exact only if the E6_s0 stem runs elsewhere, e.g. on qb_lane_w) | 6316.2 | -12.4 % | 240 | 3605 / 440 / 613 |
| qb_lane_sc | (c) late operands, 3 stages, rounding as the carry-in, mode 1 through the multiplier; baseline widths | 6658.2 | -7.7 % | 163 | 3651 / 1882 (fin) |
| qb_lane_n + hook | (d) `set_dp_smartgen_options -booth_encoding true` | 7214.0 | 0 | 259 | identical netlist: DC already picks Booth |
| qb_lane_n + hook | (d) `-booth_encoding false` | 7831.1 | +8.6 % | 259 | |
| qb_lane_n + hook | (d) `-optimize_for area` | 8852.0 | +22.7 % | 259 | fails 500 MHz (fmax tt 471.8) |
| qb_lane_s | (a)+(c), per-channel 4-b window [9, 24], MW 27 | 5747.8 | -20.3 % | 151 | 3596 / 1111 (fin) |
| qb_lane_sk | (a)+(b const)+(c), MW 36, no shifter | 5742.7 | -20.4 % | 141 | 4136 / 636 (fin) |
| qb_lane_sp | (a)+(b per-pass)+(c), MW 34 | 6361.9 | -11.8 % | 158 | 4147 / 1121 (fin) |
| **qb_lane_s8** | **(a)+(c), per-channel 3-b window [17, 24], MW 29 (DC default Booth = (d))** | **5658.8** | **-21.6 %** | **144** | 3746 / 922 (fin) |

In the qbs_new rows, "fin" is u_fin: the window shift, 4-operand add, saturation, compare and mode mux, all in one stage.

**Best: qb_lane_s8, 5658.8 um2 (-1555 um2, -21.6 %).** Its PT fmax is 501.3 MHz at tt and 322.7 MHz at ss.

Its breakdown:

| part | um2 |
|---|---|
| multiplier 16x29 | 3745.8 |
| fin | 921.6 |
| S0 regs, x / m / mode / vld (45 b) | 321.5 |
| late regs, h / r / T (48 b) + sh (3 b) | 348.8 |
| P register (26 b + vld / mode) | 191.5 |
| output regs | 123.1 |

Notes on the variants:
- (d) on qb_lane_s8 gives the same picture: Booth forced gives 5658.8 (the same netlist), non-Booth 6377.4, and optimize_for area 6673.0 (fails at 448.6 MHz).
- Relaxed clock: qb_lane_s8 is 5025.2 um2 at 4.0 ns (multiplier 3292). At most about 450 um2 could therefore be recovered by pipelining the multiplier, and a 2-stage multiplier needs at least about 60 extra flops (about 400 um2), so this was not pursued.
- (b) never pays here. Common shifts force a wider multiplier, and the 3-b per-channel shift field costs only 20 um2 of flops plus a 3-level mux on 26 b.

Interface of qb_lane_s8 (qbs_new #(XW 16, MW 29, TW 16, SHW 3, SB 17)):
- **Inputs.** In cycle n: vld, mode, x, m'. In cycle n+1: h, r, t, sh = s' - 17.
- **Outputs.** Outputs follow edge n+2, so latency is 3 (it was 4). There is still one output per cycle, and no h/r/T/sh flops are carried.
- **Compiler-side contract.**
  - m' and sel come from `workload.py --lane-export` (the per-channel smallest exact m' with s' in [17, 24]).
  - T is clamped to [-32768, 32767].
  - |y| < 2^17 holds over the in-scope domains (max 129282).
  - In mode 1 the lane forces m = 2^17 and h = r = 0, and adds 1, so b = (x >= T) is computed as x + 1 > T. This needs x <= 32766; the c1 accumulator is at most 750.

## 4. Self-check (`hw/tb/run_tb_s.sh`, `gen_s.py` reference written from the definitions, Verilator 5.050; raw lines in `lane_tb.txt`)

- **Random vectors: PASS, 0 errors on qb_lane_s8.** 200,000 random vectors (seed 7) covered x over 16 b, m over 29 b with |y| < 2^17, every sel value, h/r/T over 16 b, 15 % mode 1, and the corners (x = -32768 / 32767 / 0 / +-1, m = 0 / 1 / max / largest legal, h, r = +-32767 / -32768, T = y_sat +- 1 and +-full scale).
- **Real parameters: PASS, 0 errors on both seeds.**
  - E6_s0: 1,162,904 requant vectors, which is every channel of every in-scope requant over its whole worst-case x domain. The DUT used the converted (m', sel); the reference used IntBin's original 31-bit (m0, sh), real h (c2h / sch), random r and real T1. There were also 24,912 mode-1 vectors (c1 domain x real T2).
  - E6_s1: 1,178,704 requant + 24,832 mode-1 vectors.
- **qb_lane_s (4-b window, MW 27): PASS** on random and on real E6_s0.
- **Also PASS on random vectors:** qb_lane_sk, qb_lane_sp, qb_lane_sc, qb_lane_h and qb_lane_sa.
- **The bench catches mutants of qb_lane_s8 (errors on random / real E6_s0):**
  - rounding carry removed: 47983 / 485102
  - `>` changed to `>=`: 48215 / 88
  - mode-1 carry-in removed: 3500 / 54

## Flag (outside this lane's scope, unchanged from qb_lane_n)

The worst-case identity-shortcut output can exceed 16 b: idm y reaches 40160 (E6_s0 b0) and 45032 (E6_s1 b3) when the stream is at 32767.
IntBin keeps rs unclamped, but the lane saturates it to +-32767 and r is 16 b. So r = rs is exact only while |rs| <= 32767.
This needs a range check in the compiler or a 17-b r. It applies to qb_lane_n as well.

## qb_lane_f: fused lane for the p2 golden (`hw/rtl/qb_lane_f.sv`)

Golden: `qc18bacc.golden_p2.IntBin2` (results/golden_p2.md). Every identity requant idm is the shift j in {0, -1}, so the second 16 x 29 idm multiplier of the old fused lane (cycles.md deviation 5) is gone.

**Function.** It is qb_lane_s8 (qbs_new: window requant s' = 17 + sel, late operands, rounding as the carry-in, 3 register stages, latency 3) plus the following:
- the compiler deviations of cycles.md: per-channel sign(g) negate of the 20-b accumulator, a 16-b bias pre-add (stem), input ReLU, a per-channel pre-clamp [lo, hi] to 16 b, the [0, 127] output clamp (u8 mode) and a 17-b r output (r mode).
- the p2 residual, selected by `rmode` from the 17-b stream entry `sv`: 0 none, 1 r (conv-shortcut blocks), 2 relu(s_in) (j = 0), 3 (relu(s_in) + 1) >> 1 (j = -1). It is computed before the late register and needs no multiplier.
- the b1_next compare: b = sat16(y + h + rs) > T1_next (sat mode only).

Mode 1 (b2 = x >= T2) is dropped, because v1.1 runs binary c1 on the per-PE comparators.

**Interface.**
- Cycle n: vld, relu, acc (20 b), sgn, bias, lo, hi, m.
- Cycle n + 1: sel (4 b), h, sv (17 b), rmode, omode, T.
- Outputs follow edge n + 2: vld_o, y_o (17 b), b_o.
- The pre-processing (negate, + bias, ReLU, clamp) is combinational in front of the S0 register, in cycle n. It meets 500 MHz tt with the 20 % IO-delay budget.

### p2 lane widths (`workload.lane_widths` on the IntBin2 programs; results/lane_widths_E6_s{0,1}_p2.txt, lane_export_E6_s{0,1}_p2.txt)

| | E6_s0 IntBin | E6_s0 p2 | E6_s1 IntBin | E6_s1 p2 |
|---|---|---|---|---|
| MW in qb_lane_s8's window s' in [17, 24], stem + c2m + scm | 29 | **28** | 28 | **27** |
| sel used (stem / c2m, scm) | 0-6 / 0-2 | 0-6 / 0-3 | 0-4 / 0-3 | 0-4 / 0-3 |
| idm | 24-b multiplier, sel 3-7 | shift j (b1: -1, others 0) | 24-b multiplier, sel 4-7 | shift j (b0: -1, others 0) |
| b6.hm on the fused lane (v1.1 change 1) | s' in [17, 24], MW 15 | **s' 29**, MW 22 | s' in [17, 24], MW 15 | s' 23, MW 16 |
| max binary r (idm rs / sc r) | 40160 | 32767 / 15703 | 45032 | 32767 / 12965 |
| bias pre-add range (stem) | | [-3004, 975] | | [-1109, 1035] |

Changes vs qb_lane_s8:
- **MW 29 -> 28.**
- **sel 3 -> 4 b (s' in [17, 32]).** E6_s0's p2 b6.hm needs s' = 29, which qb_lane_s8's window [17, 24] cannot reach. With 3 b, b6.hm returns to the wide lanes: E6_s0 at NL 256, NW 32 then takes 3710.8 instead of 3370.8 cycles / image (-9.2 % with 4 b). The 4-b field costs 140 um2 / lane (qb_lane_f3 below).
- **r 17 b is no longer needed.** Binary r is at most 32767 under p2, so a 16-b r / stream entry would suffice. qb_lane_f keeps the specified 17-b sv port.
- **The pre-clamp is redundant under p2.** Every pass on the fused lanes (stem, binary sc / c2, b6.hm) has an input domain that already fits 16 b. clamp(lane(x)) is monotone in x and exact on [lo, hi], so the pre-clamp changes no output. Evidence: the "lower pre-clamp removed" mutant gives 0 errors on all real vectors, and qb_lane_fn (no pre-clamp) passes both seeds. The pre-clamp only becomes necessary if a > 16-b block-6 pass is moved to the fused lanes.

### Synthesis (tt compile, 2.0 ns, same flow as above; raw lines in lane_runs.txt)

| top | function | area um2 | regs | fmax tt / ss MHz | latency |
|---|---|---|---|---|---|
| qb_lane_s8 (reference) | IntBin in-scope requant, mode 1, 16-b r | 5658.8 | 144 | 501.3 / 322.7 | 3 |
| old fused estimate (cycles.md dev. 5) | qb_lane_s8 + second 16 x 29 idm multiplier (+ ~3000) | ~8660 | | | |
| **qb_lane_f** | **p2 fused lane, MW 28, sel 4 b, pre-clamp** | **6726.2** | 148 | 501.1 / 318.0 | 3 |
| qb_lane_f3 | the same with sel 3 b (qb_lane_s8 window) | 6585.8 | 145 | 501.1 / 321.4 | 3 |
| qb_lane_fn | qb_lane_f without the pre-clamp (exact for p2) | 6339.2 | 148 | 500.9 / 321.9 | 3 |

qb_lane_f against the two references:
- **vs qb_lane_s8:** +1067 um2 (+18.9 %).
- **vs the old fused estimate:** about -1930 um2 (-22 %).
- **At NL = 256:** 1.72 mm2 of fused lanes (qb_lane_fn: 1.62 mm2), against 1.45 mm2 for 256 x qb_lane_s8. The s8 figure covers only the requant; the bias, residual and modes are not included.

Breakdown of qb_lane_f against qb_lane_s8 (um2):

| part | qb_lane_f | qb_lane_s8 | note |
|---|---|---|---|
| multiplier (u_mul) | 3604.7 | 3745.8 | 16 x 28 vs 16 x 29 |
| fin: window shift, 4-operand add, sat, u8 clamp, omode mux, compare (u_fin) | 1234.1 | 921.6 | 4-b shift, 17-b output, u8 / r modes |
| pre: negate, + bias, ReLU, pre-clamp (u_pre) | 713.5 | - | 329.8 without the pre-clamp |
| p2 residual select / round (u_res) | 155.2 | - | replaces the ~3000 um2 idm multiplier |
| S0 registers, x / m / vld (u_rin) | 307.8 | 321.5 | |
| late registers, rs 17 / h / T / sel 4 / omode (u_rlate) | 376.2 | 348.8 | |
| P register (u_rp1) | 198.4 | 191.5 | 28 b + vld (the whole product above bit 16) |
| output registers (u_rout) | 130.0 | 123.1 | 17-b y |

### Self-check (`hw/tb/run_tb_f.sh`; reference `hw/tb/gen_f.py` written from the definitions; real rows from `hw/tb/export_f.py`; Verilator 5.050; raw lines in lane_tb.txt)

- **Random vectors: PASS, 0 errors.** 200,000 vectors (seed 7), reference = the lane arithmetic.
  - Fields: acc 20 b, sgn, bias 16 b, relu, lo / hi, m 28 b, every sel 0-15, h 16 b, sv 17 b, every rmode x omode (about 16.7k each), T.
  - Corners: acc +-2^19, m 0 / 1 / max, h / sv extremes, T = y_sat +- 1.
  - Contracts: |y| < 2^17, and r mode |s| < 2^16.
- **Real IntBin2 parameters: PASS, 0 errors on both seeds.** The reference is IntBin2's own formula, using its original 31-b (m0, sh) and the idm (2^30, 30 - j). The DUT gets the raw accumulator, sign(g), bias, pre-clamp and converted (m', sel).
  - Coverage: every channel of the stem, binary sc, binary c2 (r and idm j = 0 / -1) and the moved b6.hm, each over EVERY x' of its worst-case domain. The hm parameters are per-tensor, so its 256 identical channel rows are run once over [-32767, 32767].
  - sv: uniform over the r range (sc blocks) or over [-32767, 32767] (identity blocks), plus corners. T is the real T1_next.
  - E6_s0: 1,064,599 vectors. E6_s1: 1,080,399 vectors.
- **Mutants detected (errors on random / real E6_s0):**
  - j = -1 round half up dropped: 8838 / 1996
  - one's-complement negate: 6787 / 21259
  - lower pre-clamp removed: 20054 / 0. The real count is 0 because the pre-clamp is output-invariant on the p2 domains, as stated above.
