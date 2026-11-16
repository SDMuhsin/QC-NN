# R7a: which net classes use the routing capacity of the r6c_h hub hotspots (measurement only)
**[S]** from r6c_h on tau3 (db/grt.odb, route.guide, rpt/gr_congestion.rpt); **[E]** estimate.  Scripts `impl/r7a/`
(`dump_grt.tcl` reuses `impl/r6a/net_dump.tcl`; `obs.tcl`; `classify.py` imports `impl/r6a/cuts.py`); tables `results/r7a/`.

**Method.** 818 099 nets -> 719 200 root nets (rsz `wire*` / `max_length*` ... and CTS `clkbuf_*` trees collapsed onto
the net they buffer).  Class = driver kind (block pin name, macro type + pin, RTL hierarchy) + sinks; the qb_top
glue's flattened comb nets (`u_top/nNNN`) by their comb cone: source tags propagated forward (S macro QA, map Q, block
`f_y` / `w_y` / `b2`, `rq_r`) and sink tags backward (act supply, S / map write regs + macro inputs).  "S-read rotator"
= glue comb fed by S QA, ending in qb_act2; "write-back rotators" = glue comb fed by f_y / w_y / b2, ending in the S /
map write port (incl. the HQ / HQD / Z / fused selects).  Wire = guide strip, gcell centre to centre (3-um gcells);
H = M3 / M5 / M7, V = M2 / M4 / M6.  Capacity [E]: GRT rule 10 tracks / layer / gcell (0.2-um pitch, 30 % adjust)
minus OBS (S / map / params macros block M1-M3, column blocks M1-M6, M7 10 %); check vs the GRT report's own
capacity at overflowed gcells: south H 21.0 [S] vs 21.6 [E] per gcell; guide H wire 21.2 m vs GRT usage 22.5 m [S].
Overflow share = each overflowed gcell's overflow split over the classes of the nets listed there, by count.

## 1. Hotspot totals [S / E]
| hotspot (um) | H demand / capacity | V demand / capacity | overflowed gcells H / V (of 277 778) |
|---|---|---|---|
| south x 1000-3500, y 1000-2000 | 21.2 / 18.0 m = **118 %** | 19.2 / 15.8 m = **121 %** | 200 421 / 175 010 |
| west x 0-1000, y 2000-4500 | 21.9 / 22.6 m = 97 % | 33.7 / 21.5 m = **157 %** | 194 267 / 247 450 |

## 2. Top classes (H / V wire in the window, % of window capacity, overflow share) [S]
| hotspot | class | bits (root nets in window) | H m (% capH) | V m (% capV) | ovf share H / V |
|---|---|---|---|---|---|
| south | write-back rotators (f_y / w_y / b2 -> S / map write) | 49 178 (cone nets) | 4.61 (25.6) | 5.55 (35.1) | 16.8 / 29.8 % |
| south | block `f_y` outputs (4 352 b) | 4 008 | 3.81 (21.1) | 2.87 (18.2) | 20.4 / 16.5 % |
| south | S-read rotator (s_mq -> s_q -> qb_act2) | 3 146 | 2.92 (16.2) | 1.60 (10.1) | 20.0 / 15.6 % |
| south | next: prm staging internal / S macro Q / b2 / head | 10 069 / 2 863 / 1 011 / 11 300 | 2.77 / 1.37 / 1.00 / 0.92 | 1.29 / 1.35 / 0.45 / 0.49 | 10.8 / 9.1 / 4.4 / 4.7 % (H) |
| west | act supply internal (qb_act2) | 208 291 | 9.49 (42.1) | 15.45 (71.8) | 42.2 / 51.4 % |
| west | sequencer | 98 744 | 4.23 (18.8) | 5.66 (26.3) | 22.4 / 11.9 % |
| west | block `f_y` outputs | 1 678 | 1.96 (8.7) | 2.86 (13.3) | 8.1 / 7.1 % |
| west | next: write-back rotators / clock / glue other / act out 4 608 b | 1 916 / - / 4 669 / 4 700 | 1.64 / 1.84 / 1.06 / 1.00 | 2.39 / 2.18 / 2.69 / 1.63 | 8.4 / 6.0 / 4.7 / 3.6 % (H) |
Small (< 2 % capacity each, both windows): prm -> pf / pw / t2, s_rd, cd, w_r, params / map Q, map mux, host.

## 3. Cut crossings (segments = tracks used; capacity = perpendicular tracks, OBS-reduced [E]) [S]
| cut | used / capacity | top classes (nets crossing) |
|---|---|---|
| x = 2000, y 1000-1700.6 (band below array) | 7 727 / 6 289 = **123 %** | write-back rot 3 001, prm staging 1 170, S-read rot 739, f_y 628, b2-consumers 389, head 348, s_mq 301 |
| x = 2000, y 1000-2000 (as asked; 1700-2000 is over the array, M7 only) | 9 046 / 7 187 = **126 %** | write-back rot 3 033, S-read rot 1 280, prm staging 1 171, f_y 796, s_mq 603 |
| y = 1700.6 (true array bottom, x 860-3980) | 10 750 / 31 200 = 34 % | S-read rot 1 597, f_y 1 381, s_mq 812, write-back rot 894, t2 823 |
| x = 860 (true array west edge, y 1700-4810) | 8 809 / 31 100 = 28 % | S-read rot 1 389, write-back rot 1 099, act internal 735, f_y 725, s_mq 687, act out 312 |
| x = 1000, y 2000-4500 (as asked, over the array) | 2 157 / 7 500 = 29 % | write-back rot 697, f_y 495, t2 260, S-read 204 |
The asked lines y = 2000 / x = 1000 lie inside the array (true edges y = 1700.6, x = 860); y = 2000 has ~no M2-M6 capacity
(1 332 GRT segments cross it over the blocks, `cuts.txt`).  **The edges into the array are not the limit (28-34 %); the
limit is horizontal transport inside the south band (123 %) and local density in the west strip.**

## 4. Answers
- **South band:** write-back rotators, `f_y` outputs and the S-read rotator = 11.3 m H (53 % of H demand, 63 % of
  H capacity), ~57 % of H overflow [S].  Then prm staging internal (2.8 m, 15 % capH).  `f_y` is a horizontal bus:
  whole-die 8.2 m H for 4 352 b = 1.9 mm H per bit (to the write-back / head cone, centroids x 1.2-1.6 mm) [S].
- **Log-shift stages, partly:** S-read rotator nets span 0-12 lane pitches (195 um) flat, mean 988 um (log-shift
  signature of shift 1/2/4/8 [E]); its H in the band (2.92 m, d1-d2 levels from QA) + s_mq 1.37 m = 4.3 m = 24 % capH.
  Write-back: of 4.61 m H, 1.96 m is comb depth 1 after f_y (gather), 2.65 m depths 2-6 (rup16 / rup8 stages);
  0.71 m of it is on nets spanning < 1 lane.  Log-shift stages proper ~ 2.9 + 2.6 = **5.6 m = 31 % of H capacity, 26 % of H
  demand** [S]; with their feeds (s_mq, f_y gather) 8.9 m = 42 % of H demand.  For comparison a 2048-b 4-stage
  rotator at 195-um lane pitch needs ~7.7 m H [E: 2048 x 19.4 lanes x 195 um]; S-read measured 4.6 m whole die.
  The rest of the H demand is `f_y` (3.8 m), prm staging (2.8 m), b2 / head / glue (2.9 m): not rotator stages.
- **West strip:** local logic, not buses: qb_act2 internal + sequencer = 61 % capH / 98 % capV and 64 % / 63 %
  of H / V overflow [S]; act supply out (4 608 b) is only 4.4 / 7.6 %; f_y + write-back rotators 16 / 24 % of
  capH / capV.
