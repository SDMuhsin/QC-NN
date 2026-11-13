# Fused-lane count NL with the stream buffer S resized (NL 128 / 192 / 256, NW 32, supply config C)

Question: the fused lanes read NL and write NL 16-b stream words per cycle, so fewer lanes allow a narrower, deeper
(denser) S. Does that pay once cycles are counted?
**Answer: no. NL 256 stays best on average executed TOPS/mm2.** NL 192 loses 12 % and NL 128 loses 19-20 % under both
routed scenarios. Fewer lanes save area: lanes -0.39 / -0.78 mm2, but S changes by only +0.08 / -0.29 mm2. They also add
+648 / +1238 cycles per image (+18 % / +34 %), because every binary stage-1..4 c2 / sc pass and the stem are fused-drain
bound. Peak TOPS/mm2 rises slightly (+3 % / +10 %) only because the area falls.

Labels: [Mod] modelled (compile/supply.py + cycles.py), [S] synthesis or memory-compiler numbers (pre-route),
[E] estimate. Golden p2, v1.1 program, val[:100] (never the test set), GPU 0.

## 1. Cycles / image, config C [Mod]

Code: `compile/nl_sweep.py` (new). It runs `cycles.list_schedule(prog, st, NL, 32, ctx=2, sup=supply.Supply(width=512,
b6="S", ctx=2), check=True)` with the hazard check PASS for every NL and image. NL enters the model only as the fused
drain / hm-job length ceil(1024 / NL) per tile: 4 / 6 / 8 cycles at NL 256 / 192 / 128 (cycles.drain, list_schedule dd).
supply.py has no NL dependence. The NL 256 row reproduces supply.md C (3651.7 / 3632.9).

Command: `CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.nl_sweep /tmp/root/qc18b/exc200/E6_s0/best.pt
/tmp/root/qc18b/exc200/E6_s1/best.pt --n 100 --cache <scratchpad>/cache --json nl_sweep.json`

| NL | drain cyc / tile | E6_s0 C (min / max) | E6_s1 C (min / max) | delta vs NL 256 (s0 / s1) | C0 (two contexts, free supply) s0 / s1 |
|---|---|---|---|---|---|
| 256 | 4 | 3651.7 (3527 / 3742) | 3632.9 (3534 / 3718) | 0 / 0 | 3475.1 / 3454.2 |
| 192 | 6 | 4299.6 (4175 / 4390) | 4280.9 (4182 / 4366) | +647.9 / +648.0 | 4082.1 / 4061.2 |
| 128 | 8 | 4889.6 (4765 / 4980) | 4870.9 (4772 / 4956) | +1237.9 / +1238.0 | 4690.1 / 4669.2 |
| 128, S 2048 b (conflict bound, see 2) | 8 | <= 4929.0 | <= 4912.7 | <= +1277 / +1280 | |

Per-pass attributed cycles, E6_s0 (sum to the image). E6_s1 has identical deltas: the binary passes have no
data-dependent items, and block 6 does not change.

| pass | NL 256 | NL 192 delta | NL 128 delta | mechanism |
|---|---|---|---|---|
| stem | 160 | +120 | +250 | 64 tiles x drain (4 -> 6 / 8), drain > 2 packed items |
| b0.c1 / b1.c1 | 129 / 129 | +23 / +23 | +6 / +6 | interleave partner drain-bound (attribution shifts) |
| b0.c2 | 152 | +120 | +248 | 64 tiles, 2 items vs drain 4 / 6 / 8 |
| b1.c2 | 206 | +125 | +225 | same |
| b2.c1 | 69 | +5 | +44 | map-port supply stall 5 -> 49 (window waits behind the longer c2 drains of b1) |
| b2.sc | 57 | +55 | +112 | 32 tiles x drain |
| b2.c2 | 205 | +66 | +131 | 32 tiles, 4 items vs drain 6 / 8 |
| b3.c1 | 145 | -2 | -4 | |
| b3.c2 | 128 | +43 | +83 | 32 tiles, 4 items vs drain 6 / 8 |
| b4.c1 | 85 | -5 | 0 | |
| b4.sc | 34 | +16 | +15 | |
| b4.c2 | 155 | +23 | +50 | 16 tiles, 8 items: drain-bound only when following tiles stall |
| b5.c1 / b5.c2 | 145 / 128 | 0 / 0 | 0 / 0 | 8 items >= drain 8 |
| b6.hm | 80 | +34 | +68 | 16 fused jobs x (1024 / NL) |
| b6.c1 / sc / c2 | 371 / 69 / 907 | 0 | 0 | wide lanes (NW 32), unchanged |
| b7.c1 / b7.c2 | 135 / 163 | 0 / +2 | 0 / +4 | |
| **image** | **3651.7** | **+647.9** | **+1237.9** | |

Topology [E]. The fused drain is a parallel row shift (r1.md). At NL 128 it shifts 2 PE rows per cycle (8 cycles);
at NL 256 it shifts 4. **NL 192 is awkward:** it shifts 3 rows per cycle, and 16 rows = 5 x 3 + 1, so the drain takes
6 cycles with 2/3 of the lanes idle in the last one. That is effectively 171 lanes for the area of 192. The shadow's
3:1 input mux stays (source r + 3 instead of r + 4). The S lane map becomes lane = (pixel mod 3) x 8 + channel group
(24 lanes) at address pixel div 3, which needs a /3 address step. The 3 pixels of a drain cycle are consecutive, so
they always hit distinct lanes. NL 128 is clean: lane = (pixel mod 2) x 8 + group, 16 lanes.

## 2. S requirement per NL (program bounds) [Mod]

* **Entry width 16 b (verified).** prog.checks r bounds under p2: binary r / idm rs max = E6_s0 b0 / b3 / b5 idm
  32767, b2.sc 15703, b4.sc 9170; E6_s1 idm 32767, b2.sc 9310, b4.sc 12965. Every value is <= 32767, so r fits a
  16-b signed entry. The stream itself is sat16. Block-6 r (wide lanes, E6_s0 180737 / E6_s1 109212, i.e. 19 b) is
  stored as 2 S entries (lo / hi), as in program.py.
* **Capacity = 65 536 entries x 16 b = 1 048 576 b.** S occupancy per pass (entries written): stem / b0.c2 / b1.c2 =
  65536 (max); b2 / b3 = 32768; b4 / b5 = 16384; b6.sc r = 16384 (2 entries / output); b6.c2 / b7 = 8192. At block 6
  the live set is s5 (16384) or r (16384) plus HQ 128 kb + HQD 32 kb + Z 64 kb (224 kb, r2b layout) <= 480 kb, so the
  int8 slices fit beside the block-6 stream at every NL. The int8 slices need 112 rows of a 2048-b lane group, and
  every macro set below is at least 256 rows deep.
* **Bandwidth.** Read NL x 16 b (drain s_in / r, hm s) and write NL x 16 b (s_out). The block-6 int8 word is 2048 b read
  at one address from distinct macros (r2b). This is satisfied at every NL (N x bits >= 2048).
* **Read conflict at NL 128.** S totals 2048 b per cycle, so the int8 word takes the whole read port. The b6.c2
  wide-lane r reads (32 lanes x lo + hi = 1024 b, every cycle of a b6.c2 drain) collide with S int8 grants in
  **39.3 / 41.8 cycles / image** (E6_s0 / E6_s1 mean, max 49; counted on the config-C schedule by nl_sweep.conflicts).
  If r has priority, every such int8 read slips; the table uses + that count as an upper bound [Mod/E].
  NL 192 has no conflict: int8 uses lanes 0..15 (2048 b) and r uses lanes 16..23 (1024 b), which is exactly 24 x 128 b.
  NL 256 has none either (r2b). "NL 128 cf" = NL 128 with a 3072-b read S (conflict-free) for comparison.

## 3. Min-area S macro sets (ARM rf_2p_adv / rf_sp_adv / sram_sp_adv, TSMC 65 GP) [S]

Code: `impl/mem/s_nl.py` (new, imports mem_opt.py). It applies the same configuration rules and timing gate (tt tcyc
<= 2.0 ns, ta <= 1.2 ns). Raw lines: `impl/mem/sweep_nl.txt` (70 new shapes generated on tau1 with mc_sweep.sh under
/tmp/ckp908/qc18bacc/nlsweep; only numbers returned), plus `sweep_raw.txt`.
Command: `python3 -I qc18bacc/impl/mem/s_nl.py report qc18bacc/impl/mem/sweep_raw.txt qc18bacc/impl/mem/sweep_nl.txt`.

| NL | need (R / W b per cycle) | chosen (1R + 1W, unconditional) | macros | S mm2 | tt ta / tcyc ns | ss ta / tcyc ns | best conditional SP split (mem.md note 2) |
|---|---|---|---|---|---|---|---|
| 256 | 4096 / 4096 | rf_2p_adv 256 x 128 mux 1, 32 lanes | 32 | **2.497** | 0.740 / 0.849 | 1.198 / 1.298 | rf_sp 128 x 128 m1 x 64: 2.167 |
| 192 | 3072 / 3072 | rf_2p_adv 344 x 128 mux 2, 24 lanes | 24 | **2.577** | 0.980 / 1.097 | 1.649 / 1.684 | rf_sp 172 x 128 m2 x 48: 2.264 |
| 128 | 2048 / 2048 | rf_2p_adv 512 x 128 mux 2, 16 lanes | 16 | **2.206** | 1.050 / 1.140 | 1.758 / 1.753 | rf_sp 256 x 128 m2 x 32: 1.777 |
| 128 cf | 3072 / 2048 | rf_2p_adv 344 x 128 mux 2, 24 lanes | 24 | 2.577 | 0.980 / 1.097 | 1.649 / 1.684 | rf_sp 208 x 128 m2 x 40: 2.030 |

Halving the bandwidth buys only -0.29 mm2 (-12 %). rf_2p at 256 words with mux 1 is already near the density of the
deeper mux-2 macros (2.38 vs 2.10 um2/bit), and NL 192's non-power-of-two depth (344) is less dense than NL 256's 256 x 128.
The deeper macros are slower: tt ta 1.05 ns and ss 1.76 ns at NL 128, against 0.74 / 1.20 ns at NL 256.
Note: a 16-b S at NL 256 is 2.497 mm2, against mem.md's 17-b 2.616 (-0.119 mm2 at any NL). The conditional SP
splits are 0.31-0.43 mm2 smaller at every NL, so they do not change the ranking.

## 4. Area and executed TOPS/mm2

Area (pre-route) = logic + other macros + S, with:
* logic = 6.40 mm2 at NL 256 (core 5.353 [S] + qb_act2 0.747 [S] + control 0.30 [E]) + (NL - 256) x 6 098 um2 [S/E];
* other macros = 7.07 - 2.62 (old S) - 0.203 (Z map, now in S) = 4.247 mm2 [S];
* S from section 3, unconditional 2P choice [S].

Throughput: ops / image = 2 x 119.87 M (E6_s0) or 2 x 122.2 M (E6_s1), executed ops only; peak = 2 x 73 728 ops / cycle.
Routed scenarios [E]: **R1** = logic x 1.7 + macros x 1.15 at 400 MHz; **R2** (qc18acc pnr_v4 precedent) = total x 1.63
at 291 MHz. The pre-route 500 MHz column is shown for reference.

| NL | cycles s0 / s1 [Mod] | fused lanes mm2 | S mm2 [S] | logic mm2 | macros mm2 | pre-route mm2 | pre-route 500 MHz peak / avg s0 / s1 | R1 mm2 | **R1 peak / avg s0 / s1** | R2 mm2 | **R2 peak / avg s0 / s1** |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **256** | 3651.7 / 3632.9 | 1.561 | 2.497 | 6.400 | 6.744 | 13.144 | 5.61 / 2.50 / 2.56 | 18.64 | 3.17 / **1.41 / 1.44** | 21.43 | 2.00 / **0.89 / 0.91** |
| 192 | 4299.6 / 4280.9 | 1.171 | 2.577 | 6.010 | 6.824 | 12.834 | 5.75 / 2.17 / 2.22 | 18.06 | 3.27 / 1.24 / 1.26 | 20.92 | 2.05 / 0.78 / 0.79 |
| 128 (S 2048 b, + conflict bound) | <= 4929.0 / 4912.7 | 0.781 | 2.206 | 5.619 | 6.453 | 12.072 | 6.11 / 2.01 / 2.06 | 16.97 | 3.48 / 1.15 / 1.17 | 19.68 | 2.18 / 0.72 / 0.74 |
| 128 cf (S 3072 b) | 4889.6 / 4870.9 | 0.781 | 2.577 | 5.619 | 6.824 | 12.443 | 5.92 / 1.97 / 2.02 | 17.40 | 3.39 / 1.13 / 1.15 | 20.28 | 2.12 / 0.70 / 0.72 |

TOPS/mm2 are executed ops; avg = ops / image / cycles x f / area; [E] for the routed columns.
With the conditional SP-split S (mem.md note 2) at every NL, the averages under R1 are 1.44 / 1.26 / 1.18 (NL 256 /
192 / 128): the same ranking.

Break-even: NL 128 would need its S + lanes to save about 25 % of the routed area (~4.7 mm2 under R1:
18.64 x 3651.7 / 4889.6 = 13.92) to match NL 256's average. It saves 1.67 mm2 (lanes 0.78 x 1.7 + S 0.29 x 1.15).

## Caveats

1. Lane adjustment covers the qbf_lane cells only (6 098 um2 each, r1.md). The fused parameter bank, lane input muxes
   and drain wiring are not scaled. That overstates the area of NL 128 / 192 by well under 0.1 mm2 (fused bank 53 k um2
   in total), which is far too small to change the ranking.
2. NL 128 with a 2048-b S: the int8 / r conflict is an upper bound (+39 / +42 cycles per image), not scheduled.
   Without it NL 128 is 4889.6 / 4870.9. The ranking does not depend on it.
3. NL 192: 6-cycle drains (171 effective lanes), and a /3 lane / address map for S. Writer-side layout for HQ / HQD
   (r2b open item) is unchanged at every NL.
4. The deeper mux-2 S macros of NL 128 / 192 are slower (ss ta 1.65-1.76 ns vs 1.20). This is not a limiter at R1's
   400 MHz, but it adds no clock headroom.
5. Supply model = config C as built in R2b (cycle-exact at NL 256). NL changes only the scheduler's drain lengths, so
   the NL 128 / 192 counts carry the same model assumptions.

Checks: `compile/test_compile.py` ALL PASS after the change (new modules only; no default changed).
