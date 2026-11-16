# R7b: column-sliced south logic + full-height act supply (placement-only experiment, OpenROAD, tau3 / tau6)
**[S]** tool / script output; **[R]** reasoning.  Scripts `impl/r7b/` (opt-in, defaults of r6b / r6c
unchanged); summaries `results/r7b/`.  Recipe = r6c_h (ICG, snap3 / spread3, EST_RC 0.73/0.28, MAX_UTIL 99, buffer band
120 um, QB_SKIP_RT / QB_NOHOLD / QB_GRT_ALLOW / QB_GRT_STOP, DC buffers kept: QB_RMBUF 0) + the two constraint fixes.
**Answer: rejected for the south (slicing 2.5x the repair buffers, no legal placement); west variant worse in timing, GRT pending.**
- Sliced S (r7b_s, die 23.243, tau6; and r7b_w's first run): DRV repair adds **202.8 k / 210.3 k buffers** (r6c_h 81.1 k),
  std 5.08 / 5.17 mm2 (r6c_h 3.58), **132-136 k cells with no row within 400 um** (r6c_h 16.0 k; spread3 fallback moves
  them 3.5-3.8 mm, 20-40 k not placed at all) [S].  r7b_s then sat > 45 min in the first detailed placement (killed);
  r7b_w was switched to the west-only variant.  No GRT exists for a sliced placement.
- Cause [S, `xslice.txt`]: of 207 k nets touching the sliced cells, **18.8 k span >= 2 column slices, summed span >= 24.0 m**
  of forced horizontal wire (glue comb 14.3 m, prm 5.3 m + fetch lines 1.1 m, head 1.3 m, rq_r 0.9 m) - more than the
  south band's whole H capacity (18.0 m, R7a) and 2.6x the rotator wire R7a measured (S-read + write-back ~9 m H).
  The registers at the block-pin boundary are column-local (pf / pw / t2 staging, rq_r, s_wd, tacc / hold: 54.7 k seed
  cells), but the comb between them (f_y gather, rup16 / rup8 + S-read log stages, prm fetch fan-out, head pq / requant)
  is column-mixed at bit level [R]: assigning it to one slice turns its other-column fan-in / fan-out into long nets.
- West only (r7b_w, die **23.495** = north band +63 um for the sequencer, S = r6c_h's placement): +94.0 k repair buffers
  (r6c_h 81.1 k), 25.4 k cells without room (16.0 k), CTS WNS -14.63 ns (r6c_h -6.76 propagated) [OR est.]: the
  sequencer / W glue moved north lengthens block -> W and W -> S paths by ~3 mm.  GRT (3 iterations) still running at the
  6-h box (> 50 min; r6c_h 32 min): overflow / GRT timing not available - criterion f_est >= 20.5 x 23.495 = 481.6 MHz
  needs GRT WNS >= -0.43 ns at 1.65 ns, unreachable from CTS -14.6 ns [R].
## 1. Column slices (`slice.py`, labels on the r6c_h prep netlist) [S]
Seeds: column block pins of column c, S macro g_s_k (k % 8), map g_map_a__g_mm_b (4a + b), head tacc / hold of channel ch
(ch / 8) + every S cell whose direct block / macro / head-channel neighbours are all one column; then synchronous label
propagation (one hop / round, 15 rounds): column c if c >= 60 % of the column-labelled neighbour weight and column
weight >= 50 % of all labelled weight (shared neighbours count against), else SX (nets > 64 pins ignored).
| slice | S0 | S1 | S2 | S3 | S4 | S5 | S6 | S7 | SX (shared) | total |
|---|---|---|---|---|---|---|---|---|---|---|
| std mm2 (DC sizes) | 0.111 | 0.068 | 0.098 | 0.065 | 0.075 | 0.064 | 0.064 | 0.110 | 0.099 | 0.753 |
| rows mm2 (util) | 0.361 (0.31) | 0.153 (0.44) | 0.153 (0.64) | 0.153 (0.43) | 0.153 (0.49) | 0.153 (0.42) | 0.153 (0.42) | 0.155 (0.71) | 0.349 (0.28) | |
SX = glue 0.036 / head 0.033 / prm 0.030 mm2.  Regions (`groups.py`): Sc = x of column c, y 0-1580.6 (buffer band kept),
S0 + 200 um into the SW corner (QB7_S0W), SX = rest of it.  Uneven S0 / S7 / S2 = label creep (head pq -> S0, prm
fetch lines flt 2 800 regs -> S7).  (Harmonic averaging instead gave SX 0.41 mm2: seed-adjacent registers fall < 60 %.)
Slice group placements (`impl/r6b/grp_place.tcl` per slice): default gpl diverged (GPL-0307) in 5 of 9 slices; rerun
with `QB_GGPL "-overflow 0.35 -max_phi_coef 1.02"` (S7 / SX of r7b_w without the in-group legalisation).
## 2. West: full-height WA, sequencer north (`groups.py QB7_WEST full`, `QB7_PINS 1`) [S]
WA = whole west strip from the array bottom to the descriptors (y 1700.6-4642.6, 2.49 mm2 rows, 256.7 k cells 0.927 mm2,
util 0.37; r6c_h 1.68 mm2 / 0.55): 1.49x the r6c_h WA height (R7a V demand 157 % -> needed >= 1.57x).  W (sequencer,
169.8 k cells 0.583 mm2) = strip above the descriptors + NW corner + north band (shared with N): needs the north band
grown 120 -> 183 um (+0.252 mm2, die 3990 x 5888.4 = 23.495 mm2, cap 23.5); chip IOs moved to the west edge y 5095-5788.
W in that L shape: default gpl diverged (overflow 0.3, ~900 iterations; rerun -overflow 0.3).
r7b_w: DRV repair on 113.6 k nets (r6c_h 104.3 k), std 3.730 mm2 [S]; worst place / CTS path col 6 -> u_top/quiet_reg
(W register now ~3 mm north); CTS hold -5.93 ns is sequencer-internal (cm_de -> stb skew), no longer column act [OR est.].
## 3. Constraint fixes (both runs, from the place step on)
- **Block clk latency** (`blklat.tcl`, QB7_BLKLAT 1): `unset_clock_latency` on the 8 column clk pins before placement
  (db/place.sdc on has none); the block insertion (0.96 ns tt) stays in the ETM arcs (act setup ~-0.84 / hold ~+0.86) and
  the clk pin takes the propagated top-tree arrival after CTS (R6c QB_BLK_PROP did this only at route_pre) [S, logged].
- **ETM act / pf hold arcs** (`etm_fix.py`, QB7_ETM_FIX 1 -> `$QC_BUILD/r7b_blk`): the 5.9-8.2-ns arcs are one-edge
  extraction outliers, not the feedthrough: act[4071] rise setup -7.05 / hold +8.18 ns while its fall arcs are -0.92 /
  +0.93 (all act pins: median -0.84 / +0.86); also act[2023] rise setup -3.34, act[1160] fall 11.28 / -6.55, pf[526] rise
  -17.28 / +12.51 (`etm_fix.txt`).  Fix: when rise and fall first values differ by > 2 ns, the outlier edge's table is
  replaced by the other edge's (7 arcs tt; ss / ff none).  The R6c worst hold endpoints (act[4071], every column, -5.6
  ns, "library hold time 5.88") carried exactly this arc.  R5b false paths (act[1160] pf[526] act[265]) kept.
## 4. GRT / next [R]
r7b_w GRT checkpoint (when it finishes, tau3 `pnr/r7b_w`): `rpt/grt_classes.txt` (classes.tcl, written by post_grt.tcl),
`python3 -I impl/r7b/ovf.py rpt/gr_congestion.rpt r7b_w` vs `results/r7b/ovf_r6c_h.txt` (r6c_h: 1.10 M entries, 11.7 M
tracks; S band H 161 k / V 122 k, W strip H 183 k / V 241 k entries).  Next, if slicing is pursued: label only registers
(seeds) and leave the comb to gpl in one S group with per-slice register fences, or replicate broadcast registers per
column in RTL; the west strip needs a sequencer site within ~1 mm of WA / S (not north) at this die cap.
Files: `impl/r7b/` (run.sh, chip.cfg, place / cts_pre / blklat / classes / post_grt.tcl, slice / groups / etm_fix / ovf /
xslice.py); `results/r7b/` (slice_area, grp_slices, xslice, etm_fix, place_log, ovf_r6c_h).  tau6 `pnr/r7b_s`, tau3 `pnr/r7b_w`.
