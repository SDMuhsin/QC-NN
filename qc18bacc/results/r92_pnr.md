# R92 — init -> cts defects of the ICC2 column flow (runs r94 / r95)

Labels: [M] measured, [S] read from source, [E] estimate.  Runs from scratch through cts: r94 on tau10 (guard-bands
off), r95 on tau11 (QC_PNR_GUARD_HOLD=0.010 QC_PNR_GUARD_TRAN=0.05).  The later edits sit on main e72fbe7.

## Predictions (written 16:46 UTC, before the launch at 16:46:53 / 16:46:58) and outcome

1. **floorplan, track gate** [E 15 %] — did not happen: gate ok in both runs.
2. **place, legality gate** [E 25 %] — did not happen: total 0, overlaps 0, unplaced 0 after place_opt and clock_opt.
3. **r95 only, hold guard-band** [E 30 %] — half right: clock_opt's final optimisation added 4,814 cells against
   1,805 in r94, but nothing failed and ICC2 ends cts with fewer hold violators (124 against 193); pbank hotspot
   and feedthrough slack not measured.  The tau11 NDM build / licence risk [E 10 %] did not happen (libs 0:46).

## Items

1. **Track phase.**  PI premise corrected by measurement: [M] all 3,138 M2 / M4 / M6 pins are at x = 0.1 + 0.2 k (pin DEF
   in 2000 units / um), the rows at 5.0 + 0.2 k, and ICC2 starts a layer's tracks at core origin + the layer's
   `track_offset` (unset in our tech) — so the old tracks (x = 0.2 k) missed cell pins AND block pins, and moving the
   rows would have moved the tracks with them ([M] scratch library, core x 5.1: phase still 0).  Fix: `floorplan.tcl`
   sets `track_offset` = LEF OFFSET before `initialize_floorplan`; rows, pins, core offset stay; `P(CORE_OFFSET)` is
   a {left bottom right top} list.  Gate `qb_track_check` (common.tcl; LEF parsed by `qb_lef_grid`).
   - old floorplan (r93, read-only) [M]: `tracks FAIL ... M2 / M4 / M6 / M8 / AP v 0.000/0.100 ... pins on track M2 0,
     M3 7528, M4 0, M5 1688, M6 0, off track 3138`; r94 = r95 [M]: `tracks ok row_origin 5.0 5.0 ... M2 v 0.100/0.100
     ... pins on track M2 1401, M3 7528, M4 965, M5 1688, M6 772, off track 0` (phases shortened here).
   - Coordinator note (hub: the anchor moves to the die origin; these procs are no longer mine to edit).  [M] for that
     change: ICC2 track start = (core origin + track_offset) mod pitch, with ONE `track_offset` per layer for both
     directions (core {5.1 5.0}: M8 offset 0.3 -> vertical 0.6, horizontal 0.5), so one value cannot serve both
     when core x and y differ modulo the pitch.  The die-origin anchor itself is not wrong for ICC2.
2. **Legality gate.**  `qb_legality` (common.tcl): TOTAL, the "Two cells overlap." row over all three status columns,
   the verdict line, and the unplaced-cell count ([M] `check_legality` says "succeeded" with 220,777 unplaced
   cells); used after place_opt (place.tcl) and clock_opt (cts.tcl); report kept in rpt/<step>_legality.rpt.
   [M] r94 / r95 place and cts: `total 0 violations, cell overlaps 0, unplaced cells 0, verdict succeeded`.
3. **Hold-contract precision.**  `qb5_act_o_lat_icc2` reads report_timing at 6 significant digits; same pattern fixed in
   the init io_delay log, the `qb_io_lat` log line (4 digits) and PrimeTime's `qb_clk_arrival` (p50 was `%.3f`).
   [M] old r92 cts ff: `Le 0.320 Lc 0.360` against ICC2's own early / late 0.3245 / 0.3596; r94 cts ff: `Le 0.3275
   Lc 0.3634` = its early / late 0.3275 / 0.3634 (r95: 0.3370 / 0.3735, also equal).
4. **Clock transition limit.**  cts.tcl: 0.15 ns (SDC) during clock_opt, then QC_CLK_TRAN_MAX (default 0.25) on the
   clock path of every scenario, both on one summary line; `qb_cts_limits` reads the limits back and fails if a clock
   pin's constraining limit is above it.  [M] r94 / r95: constraining limit 0.25 on all 27,032 / 27,122 clock pins in
   all 9 scenarios; clock DRC at 0.25: 0 everywhere (r92, old flow at 0.15: 46 / 1 / 3 pins at ss / ss_rcw / wcl).
5. **Guard-bands.**  init.tcl `qb_guard` (after the SDC of each scenario) + `qb_guard_readback` (hold uncertainty read
   back at init; the design max transition reads back only once the timer runs, [M], so at cts).  Finding [M]: the
   library pin limit is 0.2825 ns at ff, 0.3234 at ml, 0.3852 at tt, so the 0.475 design limit bites only at ss /
   wcl; elsewhere ICC2 and sign-off share the library limit with no guard.  The clock-path limit is not guard-banded.
6. **Runs** launched 16:46:53 (r94, tau10) and 16:46:58 (r95, tau11) with `QC_PNR_TO=cts`; both `ok` at 17:38.
7. **max fanout.**  constraints.sdc: stated as a synthesis guideline, not a sign-off criterion; nothing enforces it.
8. **extract QoR line** removed (extract.tcl), reason in place.  Making it right = `qb_io_load; qb_io_lat extract;
   qb_qor extract` after the SPEFs (+10 min per round [E]); not done: no routed + filled database to check it on.
9. **Errors under redirect.**  [M] bare shell: `size_cell` on a missing cell under redirect puts 2 Error lines in the
   report file, 0 in the log, and `get_message_info -error_count` = 2.  `qb_icc2` (env.sh) now runs the step through
   <run>/<step>.run.tcl (step script + one QB_ICC2_MSG line with that count) and fails unless it is 0.  [M] dummy
   steps: clean -> pass; error under `catch { redirect }` -> old pass, new FAIL; uncaught -> fail; real libs step
   0; cts of r94 / r95 0.  **Needs the qb_qor hunk** (final report): [M] every init holds 1 hidden error
   (report_utilization before the floorplan, UR-013).  Floorplan, place, route, eco, outputs, extract, abstract: not
   measured — their first run under the new `qb_icc2` shows the count.
10. **NDM reuse.**  `qb_ndm` (common.tcl): the NDM name carries the first 8 md5 digits over the md5 of LEF, tech file,
    every corner .db and libs.tcl; libs.tcl builds it when absent, init.tcl references it.  [M] key cc58b713; another
    tech file -> db744f61; four corners -> 9fc06915; libs step built (0:40) then `reused (same input key)` (0:05).
    The header variable `::QB_NDM` is now unused (hunk).  Each host builds one new 722 MB NDM on its next libs step.
11. **Pin LEF provenance.**  abstract_pins.py logs `source <lef> md5 1fe3173782d17e18b27b20e5aab08457, 12356 pins
    (12354 signal, 2 power / ground), 2000 database units / um` [M, same md5 on tau10 and tau11]; the DEF it writes
    is byte-identical to before [M]; col.env states the origin ([S] repo comments: the retired OpenROAD run r5b).
12. **ZRT-543.**  [M] cts.log of r94 and r95: 0 — but r91b's was 0 too: there 6 of the 7 warnings come at the global
    route of the first route_opt (route.log line 4216, after `qb_io_lat route1`) and 1 in the second, when Zroute
    re-reads what route_auto drew.  [M] the 7 shapes: all M1, on 4 signal, 2 ctsbuf and 1 ropt net, one edge 2 - 3
    nm off the 5 nm grid; 0 of the 44,298 kit LEF shapes are off that grid, so they are router-made, not library
    geometry.  **They did not vanish** [M, coordinator's route log, 18:15]: r95 has 13 at the same point (r94 not
    there yet; r92 4 in all): all M1, 11 of them the identical 185 x 222 nm shape on pw / pf / act port nets and
    u_pbw register nets (r91b's pw[482] shape had that size; the LEF has one such M1 pin rect, on an unrelated flop).
    So: a tool-made shape recurring on the hold-fixed input paths, drawn before the first route_opt.  shape_use and
    the creating command are NOT determined — every host had a coordinator step running.  Detail-route violations
    after iterations 0 / 1 / 2: 950 / 30 / 4 (r94), 1019 / 29 / 11 (r95) against 1293 / 41 / 31 in r91b [M].
13. **I/O latency register set.**  [M] the structural commands in ICC2: all non-clock inputs 9,369, without rst_n
    9,289 = ICC2's "io pair regs" (r94 / r95 cts: 9289 in all 9 scenarios); the 80 are reached from rst_n only, a
    false path.  PrimeTime's structural definition was the wrong one: `qb_io_reg_clock_pins` now takes timed paths.
    [M] PrimeTime, DC netlist, ss: old 9,369, new 9,289, old - new = 80 (fed by rst_n only), new - old = 0; 1 s.
14. **Read-back after cts** [M], the same in all 9 scenarios: r95 hold uncertainty 0.060000, design max transition
    0.475000, clock-pin constraining limit 0.250000; r94 0.050000 / 0.500000 / 0.250000.
15. **M4 straps** [M] old (r93) = new (r94): VSS 19, low edges 7.000 + 20 k; VDD 19, 17.000 + 20 k; width 0.400.  Their
    centres now lie between M4 tracks: 4 tracks blocked per strap instead of 3 [E]; offset 2.1 would re-centre them.

## 16. r94 / r95 after cts beside r92 (tau8, old floorplan, old code) — all [M]

| | r92 | r94 | r95 (guard) |
|---|---|---|---|
| wall place / cts (peak RSS MB) | 21:29 / 24:58 (4,497 / 5,372) | 22:55 / 26:13 (4,490 / 5,335) | 22:18 / 25:47 (4,468 / 5,444) |
| cells place -> cts | 213,871 -> 215,824 | 213,844 -> 215,985 | 213,954 -> 219,149 |
| utilisation place -> cts | 0.6149 -> 0.6187 | 0.6149 -> 0.6185 | 0.6158 -> 0.6245 |
| DRV count place -> cts | 6 -> 61 | 13 -> 14 | 1 -> 3 |
| place GR overflow (both dirs) | 47 (0.01 %) | 13 (0.00 %) | 11 (0.00 %) |
| clock repeaters / levels | 333 / 10 | 336 / 11 | 381 / 12 |
| cells added by clock_opt final opt (hold + setup + DRV) | 1,620 | 1,805 | 4,814 |
| of these hold-only DEL* cells | 304 | 294 | 554 |
| legality line (place and cts) | three "0 0 0" rows, no TOTAL / overlap / verdict | total 0, overlaps 0, unplaced 0, succeeded | same as r94 |
| ICC2 hold after cts, WNS / TNS / violators | -0.04 / -0.15 / 159 | -0.04 / -0.28 / 193 | -0.03 / -0.13 / 124 |
| ICC2 setup WNS after cts | 0.14 | 0.15 | 0.14 |
| clock pins over their limit | 46 / 1 / 3 at ss / ss_rcw / wcl (0.15) | 0 (0.25) | 0 (0.25) |
| worst clock transition ff / ff_rcb / ml / ml_rcb | not in summary | 0.103 / 0.089 / 0.150 / 0.112 | 0.110 / 0.108 / 0.147 / 0.124 |
| ... ss / ss_rcw / tt / wcl / wcl_rcw | ss 0.16, wcl 0.15 (DRC report, 2 digits) | 0.172 / 0.161 / 0.116 / 0.153 / 0.141 | 0.188 / 0.189 / 0.138 / 0.168 / 0.167 |

"Hold cells" = instance count at the last minus the first `npo-clock-opt` phase of cts.log; a count by cell name needs
a tool session, and none was allowed after cts (the coordinator's route started within a minute on both hosts).
r92's 61 DRVs include its clock pins over 0.15.  Against the 0.15 build target the worst clock transition is over at
ss / ss_rcw / wcl in r94 (22 / 11 / 3 ps) and at ss / ss_rcw / wcl / wcl_rcw in r95 (38 / 39 / 18 / 17 ps); all are
under the 0.25 sign-off limit.

## How to resume

- State: r94 (tau10) / r95 (tau11) `ok` through cts; the coordinator's route runs (`r94bq` / `r95bq`); nothing of mine.
- Of the later edits only `icc2/cts.tcl` is on the hosts' f6 (md5 c6871857..., the final version; the cts steps
  themselves ran md5 6f710a19..., the same proc under `catch`, which did not fire).  The rest was tested from a copy.
- To merge (worktree vs main e72fbe7, 9 files): blocks/col/col.env, common/env.sh, floorplan/abstract_pins.py,
  icc2/{common,cts,extract,init,libs}.tcl, signoff/pt/io_lat.tcl, plus the three hunks of the final report (eco.tcl,
  `qb_qor`, `::QB_NDM`).  env.sh without the `qb_qor` hunk fails every init.
- Not run end to end with the final code (hosts busy): init.tcl (`[qb_ndm]` in create_lib, the guard-band line with
  its read-back), extract.tcl, PrimeTime sign-off with the new `qb_io_reg_clock_pins`.  Their pieces were run
  separately (procs on the r93 init label, libs step, PrimeTime on the DC netlist).
- After the merge the first libs step builds a new keyed NDM (about 40 s); ICC2_STEP lines show `tool_errors N`.
- ZRT-543 origin, on an idle host: the M1 shapes of net pw[448] in r95's route label (shape_use, the pin under them).
- My scratch, safe to delete: `/tmp/ckp908/qc18bacc/x92` on tau10 (flow copy, 722 MB test NDM, probe logs) and tau11.
