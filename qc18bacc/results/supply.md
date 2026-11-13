# Supply-aware cycle model (compile/supply.py)

Labels: [M] measured (RTL simulation), [Mod] modelled.  Golden p2, v1.1 program, NL 256, NW 32, val[:100] (never the test set), GPU 0.  Every config runs the v1.1 list scheduler (compile/cycles.py) with its hazard check on the scheduled times (PASS for every config / image).

Command: `CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.compile.supply /tmp/root/qc18b/exc200/E6_s0/best.pt
/tmp/root/qc18b/exc200/E6_s1/best.pt --n 100 --cache DIR` (stats from cycles.load_stats' cache, block-6 (plane, chunk)
masks cached next to them; masks asserted to sum to the dataflow's item counts, dataflow logits == IntBin2).
Code: `compile/supply.py` (new) + default-off hooks in `cycles.list_schedule` (`win`, `ctx` = at most ctx array passes
in flight, `sup` = supply hook: stretches a committed tile's compute to its last item issue, and selects among
candidate tiles by max(scheduler start, supply-ready start)); with the defaults cycles.py is unchanged
(v1.2 row below reproduces cycles.md; test_compile.py ALL PASS, see end).

## Summary [Mod]

| config | cycles / image E6_s0 | E6_s1 | vs v1.2 (s0 / s1) | mechanism (one line) |
|---|---|---|---|---|
| v1.2 (cycles.py as is) | 3373.1 | 3352.2 | 0 / 0 | free supply, 4-pass interleave (val[:500]: 3370.8 / 3345.1) |
| A as built | 8658.5 | 8674.0 | +5285 / +5322 | b6 re-reads HQ / Z per channel tile at 512 b (+2421 / +1498 / +531 on c1 / sc / c2), cold window per pass, b2.c1 / b4.c1 port-bound |
| B | 4241.4 | 4223.0 | +868 / +871 | b6 at rate (c1 1 word / item); left: pass-serial array (A0 +402) + cold windows (~16-25 / pass) + b2.c1 (+81), b4.c1 (+50) |
| C | 3651.7 | 3632.9 | +279 / +281 | 2nd context hides cold windows and b2.c1 behind the other pass; ctx = 2 limit costs +102 (C0); per-cycle port arbitration (R2b, was 3653.7 / 3634.9 with whole-row port slots); **built in R2b, cycle-exact vs RTL (results/r2b.md)** |
| D | 4066.4 | 4048.0 | +693 / +696 | 1024 b halves cold windows / row loads; still pass-serial |
| E | 3588.7 | 3569.9 | +216 / +218 | best: = C0 (+102, two contexts instead of 4-pass interleave) + ~114 supply |

Free-supply controls: A0 (one context) 3775.1 / 3754.2, C0 (two contexts) 3475.1 / 3454.2.  Sensitivity: B with b6.sc
read from the full HQ plane (no decimated copy, 8 words / item) 4640.6 / 4647.0 (+399 vs B).

Read-bound passes (supply stall = sum over tiles of supply-stretched minus item cycles, E6_s0 / E6_s1):
* A: b6.c1 2421 / 2421, b6.sc 1498 / 1498, b6.c2 531 / 567.
* B: b2.c1 81, b4.c1 50, then 21-25 cold-window cycles on every binary pass.
* E (best): b6.sc 22.3 / 24.8 (2 S words per item, 6 items per channel tile), b4.c1 15 / 15 (5-row window, 3 prefetch
  slots), b3.c1 / b7.c2 11 / 11 (window after the c2 producer's drain).

S read port in B..E (block 6 from S): b6.c1 streams 1 word (2048 b) per item, i.e. 2048 b / cycle sustained for its
whole span (~345 / 377 items per image); b6.sc and b6.c2 average 0.4-0.8 kb / cycle (table at the end; spans include
interleaved work in C / E).  Not modelled and to be checked by the PI: the wide-lane r reads on the same S (b6.c2
drain: 32 lanes x lo + hi x 16 b = 1024 b / cycle during its 32-cycle drains, which overlap b6.c2's own array reads,
~550 b / cycle mean), and the hm / c1 / sc writers' S write traffic (Z / r).

Caveats: (1) tiles are committed in scheduler order and the port serves loads in that order (gaps filled by the
other context); a tile delayed by the scheduler (shadow / hazard) gets no extra prefetch credit beyond what the
8-slot LB allows, so the model is slightly pessimistic.  (2) In one-context configs the next pass's window starts only
after the previous pass's done pulse (as built), counted on its first tile; the scheduler's OVH (12) is kept on top.
(3) The scheduler's just-in-time shadow start uses the item count, not the stretched time (conservative).
(4) 1024-b port: pad rows also cost 2 cycles (LB writes 2 lines / cycle).

## Method

* qb_act contexts (ctx = 1: pass-level command, as built; 2: two contexts, c1 / c2 interleave).  A context owns one
  array pass from its first tile to its last; a new pass may take a context only after the context's previous pass
  issued its last item + TAIL (done pulse) + 1 (start).  The scheduler offers tiles of at most ctx array passes.
* Binary maps (as built): virtual rows of the pass (qb_act vl: top pad row, map rows, bottom pad row for 3x3 passes
  that are not whole-map tiles; 1x1 stride-2 odd rows are skipped in 1 cycle), loaded in order through ONE map read
  port shared by all contexts, LINE = 512 b per line, 4 lines per row, `width` b / cycle (pad rows cost the same as
  read rows: one LB quarter write per line).  Row v of a context can be loaded only when it fits the 8-slot line buffer
  (v < vb + 8, vb = window base of the context's segment being issued; the slot frees when the last segment with
  vb <= v - 8 has issued its last item), after its data is written (RAW ready of the tile from the scheduler), after
  the context started the pass, and after the port finished the previous load (port served in array-tile commit
  order).  A row is usable LAT = 3 cycles after its last line left the port (m_ra reg -> macro -> rdq -> LB).
  Port arbitration (R2b, hw/rtl/qb_act2.sv): every port cycle (line, pad line, skipped row; S word) is placed on its
  own at the earliest free cycle; tiles commit in scheduler order, so an earlier-committed (older) tile's cycles are
  never displaced = a per-cycle arbiter granting the older tile (smaller commit index), cycle-exact vs the RTL
  (results/r2b.md).  One context: identical to whole-row placement (A, B, D unchanged).
* Items: a binary tile issues its items one per cycle once its whole window (vb .. vb + K) is loaded (qb_act S_BIN);
  later channel tiles of the same pixel tile reuse the window.  int8 (block 6, as built): per (channel tile, plane)
  segment, window = the plane's R rows (HQ 8, Z 4, K = R), S_WAIT -> S_FLAG -> items (only nonzero chunks) -> one
  empty S_ITER cycle; one S_CTEND cycle per channel tile (carries the zero item of an empty channel tile).
* Block 6 from S (options B..E): HQ / Z stored slice-major ((plane, chunk) contiguous) in the stream buffer S, read at
  S_W b / cycle (own port, no conflict assumed), writer-side (plane, chunk) zero flags: only words holding an executed
  slice are read (c1: slice 2048 b = 1 word; c2: slice 512 b, 4 chunks per word; sc: decimated even-pixel copy, 4096 b
  = 2 words; sc_full=True: the whole plane, 8 words), re-read per channel tile, items back to back (no flag / empty
  cycles), the 16-kb line buffer holds at most 8 words not yet consumed.
* Array tile duration = (last item issue) - (scheduler start); array items and drain occupancy (shadow / lanes) stay
  the scheduler's.  So tile cycles = max(items, drain, supply) as the scheduler composes them.

## Agreement with R2 (qb_act RTL, standalone passes, E6_s0 val 0 / 1)

Model `standalone()` = config A's supply model run pass by pass from a cold qb_act, as the R2 bench does.

| pass | R2 img0 [M] | model img0 [Mod] | R2 img1 [M] | model img1 [Mod] |
|---|---|---|---|---|
| stem | 148 | 148 | 148 | 148 |
| b0.c1 | 148 | 148 | 148 | 148 |
| b0.c2 | 148 | 148 | 148 | 148 |
| b1.c1 | 148 | 148 | 148 | 148 |
| b1.c2 | 148 | 148 | 148 | 148 |
| b2.c1 | 144 | 144 | 144 | 144 |
| b2.sc | 90 | 90 | 90 | 90 |
| b2.c2 | 148 | 148 | 148 | 148 |
| b3.c1 | 148 | 148 | 148 | 148 |
| b3.c2 | 148 | 148 | 148 | 148 |
| b4.c1 | 113 | 113 | 113 | 113 |
| b4.sc | 52 | 52 | 52 | 52 |
| b4.c2 | 152 | 152 | 152 | 152 |
| b5.c1 | 152 | 152 | 152 | 152 |
| b5.c2 | 152 | 152 | 152 | 152 |
| b6.c1 | 2774 | 2774 | 2806 | 2806 |
| b6.sc | 1718 | 1718 | 1718 | 1718 |
| b6.c2 | 1212 | 1212 | 1212 | 1212 |
| b7.c1 | 152 | 152 | 152 | 152 |
| b7.c2 | 152 | 152 | 152 | 152 |
| **sum of 20 passes** | 8047 | 8047 | 8079 | 8079 |

Passes that differ from the RTL: 0 of 40 (cycle-exact on both images).

## Cycles / image [Mod] (mean over val[:100]; min / max)

| config | mechanism | E6_s0 | E6_s1 | delta vs v1.2 (E6_s0) |
|---|---|---|---|---|
| v1.2 | cycles.py as is: free supply, up to WIN = 4 passes interleaved | 3373.1 (3254 / 3462) | 3352.2 (3254 / 3438) | +0.0 |
| A0 | one context (pass-serial array), free supply | 3775.1 (3656 / 3864) | 3754.2 (3656 / 3840) | +402.0 |
| A | as built: 512-b map port, one context, b6 per-plane LB windows | 8658.5 (8605 / 8694) | 8674.0 (8630 / 8719) | +5285.4 |
| B | A + b6 slice-major in S at 2048 b/cycle, executed slices only | 4241.4 (4116 / 4332) | 4223.0 (4124 / 4308) | +868.3 |
| C0 | two contexts, free supply | 3475.1 (3356 / 3564) | 3454.2 (3356 / 3540) | +102.0 |
| C | B + two contexts sharing the 512-b map port | 3651.7 (3527 / 3742) | 3632.9 (3534 / 3718) | +278.5 |
| D | B with a 1024-b map port | 4066.4 (3941 / 4157) | 4048.0 (3949 / 4133) | +693.3 |
| E | C with a 1024-b map port | 3588.7 (3464 / 3679) | 3569.9 (3471 / 3655) | +215.5 |
| B-scfull | B, b6.sc from the full HQ plane (no decimated copy) | 4640.6 (4452 / 4796) | 4647.0 (4524 / 4796) | +1267.5 |

### Per pass, E6_s0 (attributed cycles [Mod]; supply stall = sum over tiles of (supply-stretched - item) cycles, mean)

| pass | items | v1.2 | A0 | A | B | C0 | C | D | E | B-scfull | stall A | stall B | stall C | stall D | stall E |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| stem | 128.0 | 136.0 | 254.0 | 270.0 | 270.0 | 136.0 | 160.0 | 264.0 | 150.0 | 270.0 | 16.0 | 16.0 | 16.0 | 10.0 | 10.0 |
| b0.c1 | 128.0 | 128.0 | 128.0 | 149.0 | 149.0 | 128.0 | 129.0 | 143.0 | 132.0 | 149.0 | 21.0 | 21.0 | 1.0 | 15.0 | 4.0 |
| b0.c2 | 128.0 | 134.0 | 254.0 | 275.0 | 275.0 | 134.0 | 152.0 | 269.0 | 140.0 | 275.0 | 21.0 | 21.0 | 8.0 | 15.0 | 0.0 |
| b1.c1 | 128.0 | 128.0 | 128.0 | 149.0 | 149.0 | 128.0 | 129.0 | 143.0 | 132.0 | 149.0 | 21.0 | 21.0 | 1.0 | 15.0 | 4.0 |
| b1.c2 | 128.0 | 195.0 | 254.0 | 275.0 | 275.0 | 195.0 | 206.0 | 269.0 | 198.0 | 275.0 | 21.0 | 21.0 | 8.0 | 15.0 | 0.0 |
| b2.c1 | 64.0 | 64.0 | 64.0 | 145.0 | 145.0 | 64.0 | 69.0 | 79.0 | 72.0 | 145.0 | 81.0 | 81.0 | 5.0 | 15.0 | 8.0 |
| b2.sc | 32.0 | 32.0 | 125.0 | 139.0 | 139.0 | 32.0 | 57.0 | 137.0 | 41.0 | 139.0 | 14.0 | 14.0 | 10.0 | 12.0 | 0.0 |
| b2.c2 | 128.0 | 137.0 | 128.0 | 149.0 | 149.0 | 218.0 | 205.0 | 143.0 | 214.0 | 149.0 | 21.0 | 21.0 | 2.0 | 15.0 | 2.0 |
| b3.c1 | 128.0 | 128.0 | 128.0 | 149.0 | 149.0 | 128.0 | 145.0 | 143.0 | 139.0 | 149.0 | 21.0 | 21.0 | 17.0 | 15.0 | 11.0 |
| b3.c2 | 128.0 | 128.0 | 128.0 | 149.0 | 149.0 | 128.0 | 128.0 | 143.0 | 128.0 | 149.0 | 21.0 | 21.0 | 0.0 | 15.0 | 0.0 |
| b4.c1 | 64.0 | 64.0 | 64.0 | 114.0 | 114.0 | 64.0 | 85.0 | 98.0 | 79.0 | 114.0 | 50.0 | 50.0 | 21.0 | 34.0 | 15.0 |
| b4.sc | 16.0 | 25.0 | 61.0 | 80.0 | 80.0 | 25.0 | 34.0 | 76.0 | 28.0 | 80.0 | 19.0 | 19.0 | 0.0 | 15.0 | 0.0 |
| b4.c2 | 128.0 | 143.0 | 128.0 | 153.0 | 153.0 | 164.0 | 155.0 | 145.0 | 161.0 | 153.0 | 25.0 | 25.0 | 0.0 | 17.0 | 0.0 |
| b5.c1 | 128.0 | 128.0 | 128.0 | 153.0 | 153.0 | 128.0 | 145.0 | 145.0 | 137.0 | 153.0 | 25.0 | 25.0 | 17.0 | 17.0 | 9.0 |
| b5.c2 | 128.0 | 128.0 | 128.0 | 153.0 | 153.0 | 128.0 | 128.0 | 145.0 | 128.0 | 153.0 | 25.0 | 25.0 | 0.0 | 17.0 | 0.0 |
| b6.hm | 0.0 | 80.0 | 80.0 | 80.0 | 80.0 | 80.0 | 80.0 | 80.0 | 80.0 | 80.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| b6.c1 | 345.0 | 371.2 | 371.2 | 2792.2 | 371.2 | 371.2 | 371.2 | 371.2 | 371.2 | 371.2 | 2421.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| b6.sc | 46.3 | 46.3 | 229.8 | 1727.6 | 252.1 | 46.3 | 68.6 | 252.1 | 68.6 | 651.3 | 1497.8 | 22.3 | 22.3 | 22.3 | 22.3 |
| b6.c2 | 678.2 | 905.6 | 722.2 | 1252.8 | 732.2 | 905.6 | 906.8 | 732.2 | 906.8 | 732.2 | 530.6 | 10.0 | 1.2 | 10.0 | 1.2 |
| b7.c1 | 128.0 | 128.0 | 128.0 | 135.0 | 135.0 | 128.0 | 135.0 | 128.0 | 128.0 | 135.0 | 7.0 | 7.0 | 7.0 | 0.0 | 0.0 |
| b7.c2 | 128.0 | 144.0 | 144.0 | 169.0 | 169.0 | 144.0 | 163.0 | 161.0 | 155.0 | 169.0 | 25.0 | 25.0 | 19.0 | 17.0 | 11.0 |
| **image** | | **3373.1** | **3775.1** | **8658.5** | **4241.4** | **3475.1** | **3651.7** | **4066.4** | **3588.7** | **4640.6** | | | | | |

S read demand of the block-6 passes, E6_s0 (b / cycle over the pass's span = first array start .. last item; mean over images) [Mod]; the S read port runs at 2048 b / cycle while streaming

| pass | bits read / image | B | C | D | E |
|---|---|---|---|---|---|
| b6.c1 | 706478 | 2048 | 2048 | 2048 | 2048 |
| b6.sc | 189727 | 752 | 224 | 752 | 224 |
| b6.c2 | 378634 | 550 | 410 | 550 | 410 |

### Per pass, E6_s1 (attributed cycles [Mod]; supply stall = sum over tiles of (supply-stretched - item) cycles, mean)

| pass | items | v1.2 | A0 | A | B | C0 | C | D | E | B-scfull | stall A | stall B | stall C | stall D | stall E |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| stem | 128.0 | 136.0 | 254.0 | 270.0 | 270.0 | 136.0 | 160.0 | 264.0 | 150.0 | 270.0 | 16.0 | 16.0 | 16.0 | 10.0 | 10.0 |
| b0.c1 | 128.0 | 128.0 | 128.0 | 149.0 | 149.0 | 128.0 | 129.0 | 143.0 | 132.0 | 149.0 | 21.0 | 21.0 | 1.0 | 15.0 | 4.0 |
| b0.c2 | 128.0 | 134.0 | 254.0 | 275.0 | 275.0 | 134.0 | 152.0 | 269.0 | 140.0 | 275.0 | 21.0 | 21.0 | 8.0 | 15.0 | 0.0 |
| b1.c1 | 128.0 | 128.0 | 128.0 | 149.0 | 149.0 | 128.0 | 129.0 | 143.0 | 132.0 | 149.0 | 21.0 | 21.0 | 1.0 | 15.0 | 4.0 |
| b1.c2 | 128.0 | 195.0 | 254.0 | 275.0 | 275.0 | 195.0 | 206.0 | 269.0 | 198.0 | 275.0 | 21.0 | 21.0 | 8.0 | 15.0 | 0.0 |
| b2.c1 | 64.0 | 64.0 | 64.0 | 145.0 | 145.0 | 64.0 | 69.0 | 79.0 | 72.0 | 145.0 | 81.0 | 81.0 | 5.0 | 15.0 | 8.0 |
| b2.sc | 32.0 | 32.0 | 125.0 | 139.0 | 139.0 | 32.0 | 57.0 | 137.0 | 41.0 | 139.0 | 14.0 | 14.0 | 10.0 | 12.0 | 0.0 |
| b2.c2 | 128.0 | 137.0 | 128.0 | 149.0 | 149.0 | 218.0 | 205.0 | 143.0 | 214.0 | 149.0 | 21.0 | 21.0 | 2.0 | 15.0 | 2.0 |
| b3.c1 | 128.0 | 128.0 | 128.0 | 149.0 | 149.0 | 128.0 | 145.0 | 143.0 | 139.0 | 149.0 | 21.0 | 21.0 | 17.0 | 15.0 | 11.0 |
| b3.c2 | 128.0 | 128.0 | 128.0 | 149.0 | 149.0 | 128.0 | 128.0 | 143.0 | 128.0 | 149.0 | 21.0 | 21.0 | 0.0 | 15.0 | 0.0 |
| b4.c1 | 64.0 | 64.0 | 64.0 | 114.0 | 114.0 | 64.0 | 85.0 | 98.0 | 79.0 | 114.0 | 50.0 | 50.0 | 21.0 | 34.0 | 15.0 |
| b4.sc | 16.0 | 25.0 | 61.0 | 80.0 | 80.0 | 25.0 | 34.0 | 76.0 | 28.0 | 80.0 | 19.0 | 19.0 | 0.0 | 15.0 | 0.0 |
| b4.c2 | 128.0 | 143.0 | 128.0 | 153.0 | 153.0 | 164.0 | 155.0 | 145.0 | 161.0 | 153.0 | 25.0 | 25.0 | 0.0 | 17.0 | 0.0 |
| b5.c1 | 128.0 | 128.0 | 128.0 | 153.0 | 153.0 | 128.0 | 145.0 | 145.0 | 137.0 | 153.0 | 25.0 | 25.0 | 17.0 | 17.0 | 9.0 |
| b5.c2 | 128.0 | 128.0 | 128.0 | 153.0 | 153.0 | 128.0 | 128.0 | 145.0 | 128.0 | 153.0 | 25.0 | 25.0 | 0.0 | 17.0 | 0.0 |
| b6.hm | 0.0 | 80.0 | 80.0 | 80.0 | 80.0 | 80.0 | 80.0 | 80.0 | 80.0 | 80.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| b6.c1 | 377.0 | 402.9 | 402.9 | 2823.9 | 402.9 | 402.9 | 402.9 | 402.9 | 402.9 | 402.9 | 2421.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| b6.sc | 48.8 | 48.8 | 230.1 | 1728.2 | 254.9 | 48.8 | 73.6 | 254.9 | 73.6 | 678.9 | 1498.1 | 24.8 | 24.8 | 24.8 | 24.8 |
| b6.c2 | 625.3 | 850.6 | 669.3 | 1236.0 | 679.3 | 850.6 | 851.5 | 679.3 | 851.5 | 679.3 | 566.7 | 10.0 | 0.9 | 10.0 | 0.9 |
| b7.c1 | 128.0 | 128.0 | 128.0 | 135.0 | 135.0 | 128.0 | 135.0 | 128.0 | 128.0 | 135.0 | 7.0 | 7.0 | 7.0 | 0.0 | 0.0 |
| b7.c2 | 128.0 | 144.0 | 144.0 | 169.0 | 169.0 | 144.0 | 163.0 | 161.0 | 155.0 | 169.0 | 25.0 | 25.0 | 19.0 | 17.0 | 11.0 |
| **image** | | **3352.2** | **3754.2** | **8674.0** | **4223.0** | **3454.2** | **3632.9** | **4048.0** | **3569.9** | **4647.0** | | | | | |

S read demand of the block-6 passes, E6_s1 (b / cycle over the pass's span = first array start .. last item; mean over images) [Mod]; the S read port runs at 2048 b / cycle while streaming

| pass | bits read / image | B | C | D | E |
|---|---|---|---|---|---|
| b6.c1 | 772014 | 2048 | 2048 | 2048 | 2048 |
| b6.sc | 199885 | 784 | 249 | 784 | 249 |
| b6.c2 | 347832 | 548 | 399 | 548 | 399 |
