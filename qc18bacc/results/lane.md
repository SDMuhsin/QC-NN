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
