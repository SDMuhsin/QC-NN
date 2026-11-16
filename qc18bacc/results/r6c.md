# R6c: full-chip OpenROAD implementation of qb_chip (HPW144) to detailed route + PrimeTime SPEF

Labels: **[S]** tool-reported (OpenROAD geometry / STA, PrimeTime); **[OR est.]** OpenROAD STA with placement
parasitics (pre-route); **[R]** reasoning from [S] numbers; **[E]** estimate.  Hosts tau3 + tau6 (tau1 DNS failure,
tau4 / tau5 key refused).  Work dirs `/tmp/ckp908/qc18bacc/build/pnr/<tag>`.  P&R clock 1.65 ns (the DC period, as
R6b); PT sign-off at 2.0 ns with fmax = 1 / (period - WNS) (impl/r5b/pt_chip.tcl + impl/r6b/pt_extra.tcl).

**Answer (stopped by the PI after global route, ~4 h 40 min).**
- **Stage reached: global route (r6c_h, db/grt.odb on tau3) [S].**  No detailed route, DRC, antenna, SPEF or PT:
  the first DR attempt (r6c_gt, same process as GRT) was OOM-killed at track assignment (31.2 GB RSS, 30-GB host);
  DR in a fresh process from the GRT checkpoint (`run.sh dr`) had just started when it was stopped (PI: GRT timing makes DR moot).
- **Die 3990.0 x 5825.4 um = 23.243 mm2 [S]** (r6b 22.769; +0.474 = south hub band 280 -> 400 um).  Split at r6c_h
  place [S]: column blocks 9.703, macros 6.948, top std 3.577 (rows 5.583 mm2, 64.1 % full), white/halos/channels 3.015.
- **Timing [OR est., tt, 1.65 ns]:** r6c_h GRT parasitics WNS **-7.644 ns** (TNS -65 182), hold -5.590 -> ~108 MHz
  equivalent; need f >= 20.5 x 23.243 = **476.5 MHz**: **criterion not met** (and not signed off).
- **Routability [S]:** GRT with 3 congestion iterations leaves 1.10 M overflowed gcell entries (11.7 M tracks overflow)
  over the whole hub: west strip (WA/W) and south band (S), 46-54 k entries per 500-um tile.  With 15 / 50 iterations
  FastRoute was still in maze routing after 84 / 80 min.  This, not timing repair, is the binding limit: the hub top
  logic (2.6 mm2 DC + 0.85 repair buffers) and its chip-crossing buses do not fit the M2-M7 capacity of ~5.6 mm2 rows.

## 1. What was changed (all opt-in, impl/r6c; r6b / r5b / flow defaults unchanged)
- `chip.cfg`: impl/r6b/chip.cfg + MAX_UTIL `QB_MAX_UTIL` (99), antenna check on, hooks below.
- `spread3.tcl` (`QB_SPREAD3`): replaces R6b spread2 (random point in the nearest 100-um super-bin with room) by the
  nearest 20-um x row bin with room (fill 0.92, radius 400 um), then a global nearest-super-bin fallback that picks the
  closest fine bin (never a random point); dumps cells without local room to `rpt/spread3_fail_<k>.txt`.
- `snap3.tcl` (`QB_SNAP3`): row-aware version of the R6b footprint snap (no snap point off the rows).
- `icg.tcl` (`QB_ICG`): before CTS every CKLNQD is sized by its sink count (D2 <= 8, D4 <= 24, D8 <= 64, D12 <= 160,
  else D16) and moved to its sink centroid.
- `est_rc.tcl` (`QB_EST_RC "r c"`): pre-route signal RC override.
- `route_pre.tcl`: `QB_BLK_PROP` (remove the DC-hook -0.90 ns latency on the block clk pins: propagated clock),
  `QB_NOHOLD` (skip top-level repair_timing -hold), `QB_SKIP_RT` (skip the post-CTS repair), `QB_GRT_ALLOW`
  (global_route -allow_congestion), `QB_GRT_CRIT`.
- Floorplan variants via the existing R6b knobs only: `QB_SB` 280 -> 400 (south hub band, +0.48 mm2), group split
  `QB_WAH` 1830 -> 1980 (WA +150 um), group density `QB_GDENS` 0.6, and (r6c_h) the S group rectangle ending 120 um
  below the array (a template-free buffer band; edited `mplace.tcl.groups`).
- Probes (read-only): `probe_rows.tcl` (row / std area per group + repair-buffer detour), `probe_bins.tcl`,
  `probe_fail.tcl` (source of the cells spread3 could not place locally), `probe_clk.tcl`; test scripts `t_*.tcl`.
- Found on the way: impl/r6b/run.sh `grp` with a 4th (seed) argument runs `QB_SEED=...` as a command (bash
  `${4:+QB_SEED=$4}` expansion is not an assignment); used `QB_SEED` from the environment instead (not changed).

## 2. Step 1: utilisation headroom (measured first)
- **RSZ-0025 was an accounting limit, not a full die [S].**  The resizer's utilisation is (std + blocks + macros) /
  core: 0.897 at r6b_b CTS against MAX_UTIL 0.90.  The rows themselves (5.111 mm2) were 72.0 % full (std 3.679 mm2).
  But they were unevenly full: S group 81.4 %, WA 84.4 %, W 67.2 %, N 19.6 %; 100-um bins at r6b_b place: 2.71 mm2 of
  rows at 85-95 % fill vs 1.26 mm2 below 50 % (`probe_rows.tcl`, `probe_bins.tcl`).
- **MAX_UTIL 99** (run U, r6b_c CTS checkpoint = r6b_b placement): the post-CTS setup repair ran 67 min (101 490
  violating endpoints, `-repair_tns 100`) without RSZ-0025 (r6b_b aborted at 40 min); stopped by hand.  Kept as default
  of impl/r6c/chip.cfg.
- **Hub growth (G / H floorplan) [S]:** south band `QB_SB` 280 -> 400 um (+0.473 mm2 of rows under the array), WA/W
  split +150 um, group density 0.6: die 3990.0 x 5825.4 um = **23.243 mm2** (+0.474).  At place: rows 5.583 mm2, 63.2 %
  (S 61.2, WA 76.5, W 70.5 %).  Same recipe on the old die (P2) vs the new one (G): place WNS -10.24 -> -7.31 ns,
  CTS -10.59 -> -6.20 ns, hold -7.81 -> -2.74 ns [OR est.].

## 3. Step 2: clock gates
- `icg.tcl` on r6b_b place.odb (run I, CTS with R6b spread2): 4 006 ICGs -> CKLNQD2 261 / D4 1 347 / D8 2 398 (sinks
  1-8 / 9-24 / 25-64; none above 64), moved to the sink centroid, mean 214 um (max 1 277).
- **ICG output slew after CTS [S, OR est.]:** <= 0.15 ns 3 503 | 0.15-0.3 494 | 0.3-0.5 9 | 0.5-1.0 0 | > 1.0 0
  (r6b_b: 489 | 806 | 865 | 1 071 | 775); worst 0.346 ns (was 3.31).  With spread3 (run P): 3 606 | 391 | 9 | 0 | 0.
- The ICG output-net length did not improve under spread2 (> 1 mm: 489 vs 447): spread2 moved the resized ICGs again
  (random point, mean 4.2 super-bins), and CTS WNS got worse (-12.09 vs -10.78 ns).  So the ICG fix only pays together
  with the step-3 legaliser fix and the room from step 1 (G: CTS -6.20 ns).

## 4. Step 3: long-wire buffer detours (mechanism)
- **r6b mechanism [S]:** after DRV repair, R6b's snap + spread2 moved 64 694 of 159 240 movable cells by a mean of 5
  100-um super-bins to a *random* point (log), giving repair-buffer detours (driver -> buffer -> load centroid minus
  driver -> load centroid) of mean 312 um, 21 181 buffers > 300 um and 8 740 > 1 mm at r6b_b place.
- **Nearest-bin legaliser alone does not fix it [S] (run P, same die):** spread3 found no bin with room within 400 um
  for 34 491 cells; the global fallback moved them by a mean of 1 459 um, so the detour got worse (mean 464 um,
  > 1 mm 12 201) and place WNS went from -10.66 to -13.98 ns.
- **Where the rows are full [S]** (`probe_fail.tcl`, run P2): of the 33 877 cells without local room, 15 991 are
  buffer trees driven by **column-block output pins** at the array's south edge (8 x 2 702 south pins; repair_design
  puts one BUFFD16 per pin right there, the snap pushes it below the array, where the S template already fills the
  rows).  Another 9 794 are top-glue `U*` trees, 4 256 prm (`U*`, `stg_t`) and 1 992 S-macro outputs, all on nets
  crossing the array (no rows over the blocks).  Two hypotheses were tested and rejected: snapping to the array's
  east edge, which has no rows (snap3: 33 642 -> 33 877 failures, no change); and M3 RC over-buffering (QB_EST_RC
  0.73/0.28: 75 197 vs 80 443 repair cells, same failures).
- **Fix = room where the pin buffers go [S]:** G (south band +120 um) still left 22 299 cells without room (template at
  0.6 density next to the array edge).  H additionally ends the S group 120 um below the array (template-free buffer
  band, 0.452 mm2 of rows, 63 % full after DRV repair): 15 953 without room, now mostly at the array's **west** edge
  (WA act-supply nets).  Detour at place: **mean 236 um, > 300 um 13 790, > 1 mm 4 860** (r6b_b 312 / 21 181 / 8 740);
  place WNS -5.25 ns, CTS -4.99 ns (r6b_b -10.66 / -10.78) [OR est.].

## 5. Clock / constraint findings (r6c_h, after steps 1-3)
- **Block clock was ideal in OpenROAD [S]:** the P&R SDC carries the R5b DC-hook `set_clock_latency -0.90` on the 8
  column clk pins; with propagated clocks OpenSTA keeps those pins ideal (capture 0.75 ns) while top flops are at 3.3 ns.
  `QB_BLK_PROP` removes it: r6c_h CTS -4.99 -> -6.76 ns setup (63 926 endpoints instead of 116 940), hold -5.59.
- **Top clock latency:** 3.34 ns at prm flops, of which 1.86 ns is the clk-port -> CTS-root wire (0.85 pF; port on the
  west edge, root at the tree centre).
- **Hold is an ETM artefact:** the worst 100 k hold endpoints are column `act` inputs whose ETM has setup -7.0 / hold
  +8.2 ns arcs (act feedthrough chain), "library hold time 5.88 ns".  A top hold repair would insert ~6 ns of delay
  on ~1e5 nets, so it was skipped (`QB_NOHOLD`); needs a corrected ETM (or a PT check of these arcs) before sign-off.
- **Post-CTS repair is harmful in this OpenROAD build:** repair_timing -repair_tns 3 moved WNS -6.76 -> -6.43, then
  legalisation + re-estimate -> -14.76 ns (an OAI22D0 left on 0.465 pF); skipped (`QB_SKIP_RT`).

## 6. Step 4: prm stg_t -> column t2
Still the worst top -> block class at CTS (r6c_h: launch latency 3.34 ns + DFQD1 0.21 + two wire stages 1.34 / 0.86 ns
to `g_c_3/t2[88]`; t2 pins are on the block's north edge, the flops in the south hub, so the path must cross the 3.1-mm
array on M8/M9).  With propagated block clocks it is overtaken by column `f_y` -> `u_head` (ETM output 2.2 ns on
0.43 pF, 7.5 ns data at estimate).  No RTL change was made.  Both are physical-distance paths (block pin side vs hub);
a cycle-neutral fix would be an opt-in register stage near the array edge only if the schedule has slack (PI to decide).

## 7. Open issues
1. Routability of the hub (11.7 M tracks GRT overflow): needs less top logic per area (smaller DC top / fewer
   repair buffers) or more area than the 23.5-mm2 cap allows; DR on this state would be very long and DRC-dirty.
2. DR memory: GRT ~30 GB stays allocated; DR must run in a separate process (`QB_GRT_STOP` + `run.sh dr`, ready).
3. ETM act arcs (hold 5.9-8.2 ns) and the -0.9 ns block latency in the P&R SDC must be fixed before any sign-off.
4. Kerberos expiry at ~10 h dropped /CMC on both hosts mid-run (renewed with ~/bin/tau-reauth).

## Files
`impl/r6c/` (chip.cfg, place.tcl, cts_pre.tcl, route_pre.tcl, spread3.tcl, snap3.tcl, icg.tcl, est_rc.tcl,
post_grt.tcl, dr.tcl, run.sh, probe_*.tcl, t_*.tcl); `results/r6c/step_measurements.txt`, `timing_r6c.txt`,
`grt_r6c_gt.txt`.  On tau3: `pnr/r6c_h` (db up to grt.odb, route.guide, rpt/gr_congestion.rpt), r6c_p2; on tau6:
r6c_g, r6c_gt (cts_rt.odb).

