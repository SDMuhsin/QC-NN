# R92 column: route closure + gate, ECO loop with hold guard-band, shared block driver (test bed r91b)
[M] measured, [S] from source / man page, [E] estimate.  2026-11-26.  Test bed = tau4 `$B/icc2/col/r91b` (the run that
failed sign-off: 3 router DRCs = LVS short, 2 hold endpoints at wcl, one net over max_transition at ss).  Its floorplan
has the M2 track-phase bug, so this is a test of the control flow, not a sign-off candidate.

## What changed (flow/)
| file | change |
|---|---|
| `icc2/common.tcl` | `qb_route_checks` -> `qb_route_close <step>`: check_routes; up to 3 passes of `route_detail -incremental true -initial_drc_from_input true` while DRCs / antenna violations remain; hard gate: check_routes DRC / open / antenna = 0 and `check_lvs -check_child_cells true` short / open / floating = 0 (unreadable count fails); on failure the block is saved as label `<step>_fail` |
| `icc2/route.tcl` | last route_opt -> qb_fillers -> `qb_route_close route` -> qb_io_load (moved behind the closure) |
| `icc2/eco.tcl` | route_eco -> qb_fillers -> `qb_route_close`; target label `QB_ECO_TO` (eco, eco2, ...), reports / summary lines carry it |
| `signoff/pt/drv_eco.tcl` | pre-fix state -> `prefix_total` (setup + hold + max_tran + max_cap + noise, 9 corners, zero margin); 0 = converged, no change list; `QB_ECO_CHECK=1` = state only; hold fix `-hold_margin m -slack_lesser_than m` (m = `QC_ECO_HOLD_MARGIN`, 0.005 ns); state lines carry `hold_band` = endpoints with 0 <= slack < m |
| `common/block.sh` (new) | shared driver: pnr / eco (loop) / fill / calibre / post / views / signoff / rundir |
| `blocks/col/run.sh` | thin: column variables + `blk_main "$@"` |
| `common/queue.sh`, `common/status.sh` | queue.dir into the real run dir (`run.sh rundir`); status takes `<blk>/<tag>`, lists only corners with violators, shows the last ECO round and route-gate line |

## Phase 1 measurements that drove it [M]
* Leftover: net `g_r_3../g_pop2_u_pop/n1803` (U1151/ZN -> U2741/B1) routed on M1 through the 0.110 um slot under pin B1,
  overlapping U2741's internal M1 by 0.080 x 0.035 um.  First DR of route_auto: 0 violations; redundant-via insertion left
  1024; every later DR stopped at its iteration cap with 3 (route_eco: "not converging" after iteration 10).
* `check_lvs` without `-check_child_cells true`: 0 shorts on that layout; with it: 2 (n1803 x U2741, M1, the Calibre short).
* Track phase (fixed by the P&R engineer, not here): M2 track lines at x = 0.2k on site boundaries; a centred VIA1 cut
  fits 16.9 % of 555 824 signal input pins on-track, 100 % with the kit's 0.1 offset.
* Residuals after the zero-margin single ECO pass: wcl hold -0.09 / -0.04 ps (port -> flop D, crosstalk delta -14.8 /
  -17.6 ps), ss max_transition 0.5017 vs 0.5000 on one net (FA1D0, fanout 5, 101 um); none touched by the ECO.
  Endpoints with 0 <= hold slack < 5 ps: wcl 264, ss 97.

## fix_eco_timing option (PrimeTime Q-2019.12-SP2 man [S])
`-hold_margin m`: "affects the target amount of timing slack to achieve during hold fixing" (positive = overfixing), but
"for paths not already selected for hold fixing (by default, paths with zero or better slack), there is no attempt to
change the path to meet the margin requirement".  `-slack_lesser_than m`: "fixing of only the paths with a slack worse
than the specified slack limit" (default 0).  Both together = every endpoint below m is fixed to m (PI decision).
fix_eco_drc has no DRV margin: `-slack_lesser_than` > 0 only for `-type delta_delay`; its `-setup_margin` /
`-hold_margin` are timing-preservation margins (default: DRC fixing "proceeds no matter how much hold timing is
degraded") — not used.

## Test bed results
Queue `$B/icc2/col/r92q` (`- col eco|calibre|post|views|signoff r91b`), started 16:50:18 UTC from label eco.  All [M].

| step | result |
|---|---|
| eco round 1, PrimeTime DMSA (13.7 min) | pre-fix, zero margin: wcl hold 2, ss max_tran 6 -> `prefix_total 8`.  DRV pass: ss max_tran 6 -> 0 by one size_cell (U2290 FA1D0 -> FA1D1), 0 cells added.  Hold pass with the guard-band: see table below; 725 buffers (BUFFD0 610, BUFFD1 82, BUFFD2 26, BUFFD3 4, DEL005 2, BUFFD4 1; +1070 um2), 67 size_cell lines; unfixable reasons: none (every reason file "None", "remaining 0") |
| ICC2 eco, label eco -> eco2 (16.6 min) | name gate: 725 new cells, 0 missing, 0 load / record mismatch; legality 0 violations, 0 overlaps; route_eco: DR iterations 0-10, "Stop DR since not converging", 3 left; closure pass 0: DRC 3 (Short / Same net spacing / Min edge length) -> pass 1: DRC 0 (313 s); gate PASS (open 0, antenna 0; check_lvs -check_child_cells short 0, open 0, floating 0) |
| outputs, portcheck, fill, extract | OK (12 354 = 12 354 port bits; 1 505 204 fill shapes; extract 5:55) |
| eco round 2, PrimeTime DMSA (13.7 min) | pre-fix, zero margin: hold 0 in all 9 corners; ss max_tran 11; ml_rcb noise 1 -> `prefix_total 12` >= 8: step FAILED by the shrink rule at 17:42:42 UTC, queue stopped.  Its change list (6 size_cell, 17 buffers) was not applied |
| calibre on label eco2 (queue `r92q2`, 3.8 min; cal.sh of e72fbe7) | LVS CORRECT (0 bad cells), DRC 0 results (1572 rule checks, QB_ gate rule present), antenna 0; step ok |
| post on label eco2 (queue `r92q2`, 18.2 min; env.sh / col_blk.tcl of e72fbe7) | 9 corners: setup 0, hold 0 (worst port -> flop hold slack +0.003 ... +0.007 ns per corner), max_capacitance 0, clock max_transition 0 (worst 0.178 ns vs 0.25), min pulse / period 0; ss max_transition 11, ml_rcb noise 1 -> step FAILED as it must; no ETMs |
| signoff (`verdict.sh`, run by hand through run.sh) | 216 gates: 181 pass, 2 FAIL (max_transition@ss 11, noise@ml_rcb 1), 33 missing (27 ETM, 6 abstract) -> `SIGNOFF qb_col_blk FAIL`, exit status 1 passed on |
| views (run by hand through run.sh) | ICC2 abstract of label eco2 ok (abutment 4608 act pairs ok, PG pins ok, 70 s); ETM scan FAILED on the missing `out/etm/qb_col_blk_ss.lib` (post stopped before the ETMs) -> step failed |

Hold guard-band per corner, round 1 (endpoints; "selected" = slack < 5 ps before the hold pass = PrimeTime's Violation
Totals; band = 0 <= slack < 5 ps):

| corner | ss | ss_rcw | wcl | wcl_rcw | tt | ff | ff_rcb | ml | ml_rcb |
|---|---|---|---|---|---|---|---|---|---|
| violators (< 0) before | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| band before | 97 | 131 | 264 | 20 | 0 | 426 | 318 | 224 | 30 |
| selected / fixed | 97 / 97 | 131 / 131 | 266 / 266 | 20 / 20 | 0 | 426 / 426 | 318 / 318 | 224 / 224 | 30 / 30 |
| violators / band after the fix (PT prediction) | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| violators / band after ECO route + closure + extract (round 2 pre-fix) | 0 / 1 | 0 / 5 | 0 / 6 | 0 / 0 | 0 / 0 | 0 / 3 | 0 / 2 | 0 / 7 | 0 / 1 |

### Predictions vs results
* closure 3 -> 0 in one pass: CONFIRMED (scratch copies of labels route and eco, and inside round 1).
* LVS CORRECT, DRC 0: CONFIRMED on label eco2 (Calibre LVS CORRECT, DRC 0 results in 1572 rule checks, antenna 0).
* loop converges within 2 further rounds: NOT CONFIRMED.  Hold converged in one round (0 violators in 9 corners, 25
  endpoint-corners back inside the band, none below zero).  The total did not shrink because of 3 objects the ECO had
  not touched (0 lines of the change list name them):
  | object | before (label eco) | after (label eco2) | own route |
  |---|---|---|---|
  | net `g_fq_3../g_fi_6__u_lf/rsc[15]` (U86 AOI221D0 -> 1 flop D, 28 um): 2 pins, ss | 0.49981 ns, C 6.680 fF | 0.50036 (+0.55 ps), C 6.692 fF | identical |
  | net `HFSNET_2319` (HFSBUF_768_4738 BUFFD1, 28 loads, 96 um): 9 load pins, ss | 0.49941-0.49949, C 49.012 fF | 0.50003-0.50011 (+0.62 ps), C 49.081 fF | 3 objects new, 2 removed |
  | output port `b2[127]` (HFSBUF_14_3580 BUFFD8, 908 um, M6 832 um): noise below_high, ml_rcb | 0 violators (r91b post) | height 0.44, slack -0.00, 13 aggressors | identical |
  Cause: (a) zero-margin DRV fixing leaves a population at the limit: driver pins with ss transition > 0.495 ns: 12
  before, 11 after (> 0.49: 23 / 22; > 0.475: 87 / 90); fix_eco_drc has no native margin.  (b) Round 1 was not a local
  ECO: its closure pass (needed because label eco still carried the 3 DRCs) and its ECO route changed route objects on
  > 32 152 nets (66 331 new, 100 469 removed objects; shapes 2 177 329 -> 2 139 656, vias 1 898 999 -> 1 902 534), and the
  dummy fill was regenerated (1 506 932 -> 1 505 204 shapes); wire capacitance of the two nets moved +0.14 % / +0.2 %.
  A from-scratch run closes the route in the route step, so an ECO round there runs the closure pass only if route_eco
  itself leaves DRCs.  Not pushed through: no third round was run.
* post clean in 9 corners: NOT CONFIRMED: hold and setup clean in all 9; 11 max_transition pins at ss (2 nets) and 1
  noise victim at ml_rcb remain = exactly the round-2 pre-fix state of the ECO session (the DMSA state and the sign-off
  post agree).
* Where the three objects sit and what moved around them (labels eco vs eco2): `rsc[15]` at x 292-318, y 416-418:
  3 neighbour nets changed 7 route objects within 1 um (clock net cts77 M4, u_res/n65 M1, u_res/n85 M2), no ECO cell in
  the window; `HFSNET_2319` at x 251-277, y 1895-1912: 43 nets changed 124 objects in its window (M1 patches; act_o,
  acc, u_cmp nets), no ECO cell; `b2[127]`: 11 of its 13 aggressors have identical routes, 2 were re-routed
  (eco_net_18_ropt_net_4876: 1 -> 24 objects, ropt_net_4832: 36 -> 34).

## How to resume
* Where: tau4, flow snapshot `/tmp/ckp908/qc18bacc/r48` (= main checkout for every file of the table above, md5-checked,
  except `icc2/common.tcl`: r48 holds the e72fbe7 version f471eee3..., a288de7 later changed its track gate), build
  `$B=/tmp/ckp908/qc18bacc/build`, test bed `$B/icc2/col/r91b`, queue logs `$B/icc2/col/r92q` (eco) and `r92q2`
  (calibre, post).  Digest: `qc18bacc/flow/common/status.sh col/r91b`.
* r91b now: labels route / eco (3 DRCs each, old flow), eco2 (round 1 of the loop, gate PASS) and abstract (views test,
  copy of eco2); `out/` = label eco2
  (`out/label.txt`), filled and extracted; `out/eco/rounds.txt` = the two rounds; `out/eco/eco2/` = round-1 record,
  `out/eco/eco/` and `first_signoff/` = copies of the first (failing) run's ECO and sign-off files.  The round-2 change
  list `out/eco/pt_eco.tcl` (6 size_cell, 17 buffers) is NOT applied.
* The eco step is re-entrant: it reads `out/label.txt`, numbers its rounds from 1 and makes the next label (eco3).
  To continue the test bed after a decision: spec lines `- col eco r91b`, `- col calibre r91b`, `- col post r91b`,
  `- col views r91b`, `- col signoff r91b`; `common/queue.sh <new log dir> <spec>` (detached; stops at the first
  failing step).  Options per line: `QC_ECO_ROUNDS=n`, `QC_ECO_HOLD_MARGIN=ns`.
* From scratch: `- col pnr <tag>` first (`QC_PNR_FROM` / `QC_PNR_TO` for a range), then the same five lines.
* Pair rule: `common/eco_changes.tcl` + `icc2/common.tcl` (merged e72fbe7 versions) were synced to r48 at the boundary
  after round 2's PrimeTime run (17:42:58 UTC); rounds 1 and 2 ran with the old pair, the next round uses the new one
  (every round starts with PrimeTime, which deletes the old change list, so the unapplied round-2 list is never reused).
* Open: (1) PI decision on the DRV population at the limit (no native fix_eco_drc margin) and on closure passes inside
  an ECO round (block-wide re-route); (2) the sign-off engineer's hunk for the noise passes of drv_eco.tcl (act input
  nets without a holding driver); (3) fix_eco_drc's post-hold noise pass runs without a hold-preservation margin [S];
  (4) act / hub adoption of `common/block.sh`; (5) not yet run on tau4: the driver's pnr step (only its argument checks)
  and eco.tcl with the `qb_legality` call inside a round (the proc itself passes on label eco2: 0 violations, 0 overlaps,
  0 unplaced, "succeeded").
* Scratch (removable, not part of the flow): `$B/icc2/col/r92x` (Phase 1 / milestone-1 measurements, private nlib copy,
  1.4 GB+), `$B/icc2/col/r92y` (eco2 netlist + 2 SPEF copies, analysis outputs `pty_*.txt`).
