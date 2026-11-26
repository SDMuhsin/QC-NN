# R92 (sign-off half): gates that fail on evidence, one machine verdict, coverage / SI / ETM answers

Evidence: r91b and r87 on tau4, r94 on tau10 (read only); PrimeTime Q-2019.12-SP2 on a copy of r91b on tau9 (no GDS / nlib; scratch
`/tmp/ckp908/qc18bacc/r92s`).  [M] measured, [S] read from source, [E] estimate.  No Calibre / ICC2 run by this task.

## Status
- F1 - F6 are merged (e72fbe7).  Follow-up A / B / C below is in the worktree, uncommitted; the flow files are md5-equal in tau9 `f6`.
- r91b copy re-timed in all 9 corners with the follow-up scripts: timing gates as before (wcl hold 2, ss max_transition 6), noise 0,
  act_noise 0, noise_undriven_ports 0, noise_undriven_pins 0 everywhere.  r91b itself is not signed off (its LVS / DRC, no ETMs).
- Open for the PI: in the 5 slow / typical corners the decided noise state yields no recorded act bump (section A); dropping the port
  load from the noise state would give a recorded, more pessimistic bump in every corner (ss 0.281 V, still 0 violators).

## Changes
- F1 `signoff/calibre/cal.sh`: `cal_result` judges a finished lvs / drc / ant run from its files; the run modes exit 1 on a bad result;
  `cal.sh check <mode> <top> <rundir>` = the same without Calibre.
- F2 `common/eco_changes.tcl`: loads = leaf input pins + output ports, error if none; every buffer of `add_buffer_on_route` parsed.
- F3 `common/env.sh`: `qb_corners` fails on a site.tcl error / empty list; `qb_pt` needs PrimeTime's completion line, > 0 annotated
  coupling capacitances, no `^Error` in DMSA worker logs; `qb_pt -check <log>` = the gate on a finished run.
- F4 `common/env.sh` exports `QC_CLK_TRAN_MAX` (0.25), `QC_ECO_HOLD_MARGIN` (0.005); `signoff/pt/common.tcl` sets the clock-path limit
  and splits DRV violators into data / clock-network pins (`clock_max_transition`).
- F5 `signoff/verdict.sh` + `verdict.py`: GATE lines PASS | FAIL | MISSING, `VERDICT`, last line `SIGNOFF <top> PASS|FAIL`.
- F6 `common/lib_cells.tcl`: the tcq cache stores its key.  Q2 `qb_pt_coverage` (5 coverage counts) in `signoff/pt/common.tcl`.
- A `blocks/col/io_budget.tcl` (appended): `qb5_act_noise_driver [off]` = the act noise state: QB5_FT (BUFFD4/Z) as driving cell of
  every act port with the block's own feedthrough input slew of the bit, port load = the extracted wire capacitance of the own
  act_o[b] net (`wire_capacitance_max`, per bit and corner); it saves the timing state (4 input transitions per port) and `off`
  restores it.  `signoff/pt/col_blk.tcl`: `::QB_PT_NOISE_STATE` names it; every timing result (paths, clock, DRV, pulse checks) is
  written first, `qb_pt_si_checks` then enters the noise state and judges noise, and the session ends in it.  Summary lines
  `noise_state ...`, `act_noise ...`; QB_PT_SIGNOFF `noise_undriven_ports` (check_timing no_driving_cell in the noise state) and
  `act_noise` (violating act load pins); verdict.py shows both per corner.
- B `signoff/pt/lib_hold_res.py` + `qb_pt_const_hold` (common.tcl, in `qb_pt_si_checks`): the tie cells get the kit's own holding
  resistance as steady-state resistance; QB_PT_SIGNOFF `noise_undriven_pins` = check_noise's "none" count; summary line `noise_hold ...`.
- C `signoff/verdict.py`: `pnr_tracks`, `pnr_legality_place`, `pnr_legality_cts`, `pnr_route_gate`, `pnr_eco_gate` (the gate line
  of the out/ label's ECO round) from summary.txt, matched on the gate's exact line format: no such line = MISSING.

## Verification [M]
| item | test | result |
|---|---|---|
| F1 | `cal.sh check`, tau4 reports | r91b: lvs FAIL (INCORRECT), drc FAIL (4 results), ant PASS; r87: 3 x PASS |
| F2 | PT on r91b | U_PTECO_DRC_BUF20 loads `{b2[102]}` (was `{}`); 81 / 81 new cells have loads; 2-buffer line -> 2 cells; dangling buffer -> error |
| F3 | fake site.tcl; copies of a PT log | status 1 + QB_FAIL; no completion line / no coupling / worker `Error` / no .time: `evidence bad` |
| F4 | r91b, 9 corners | clock_max_transition 0 at 0.25 ns; at 0.15 ns the gate fires (8,615 clock + 6 data pins at ss) |
| F5 | tau4, first runs | r91b FAIL `max_transition@ss hold@wcl lvs drc`; r87 FAIL `noise@ml,ml_rcb`; the rest MISSING |
| A | r91b, 9 corners, with vs without the noise state | in every corner the 22 timing summary lines, the 7 timing reports (reg2reg, io, ft, min, clk, drv, pulse) and the QB_PT_SIGNOFF timing counts are identical apart from dates |
| A | in-session on -> off at ss (the ECO use) | constraints restored exactly (act input transitions identical); 1,400 path slacks and all violator lists identical at 6 digits; act_o transitions differ by <= 0.00018 ns (PrimeTime's incremental SI update depends on the session history) |
| B | check_noise, r91b | "none" 147 / 147 before; noise_undriven_pins 0 in all 9 corners with the kit resistance on the tie pins |
| C | verdict on r87, r91b (tau4), r94 (tau10) | r87: the 5 gates MISSING; r91b: 4 MISSING, pnr_eco_gate PASS (its new round eco2); r94 (route running): tracks, place, cts PASS, route gate MISSING |

Worst clock-network transition, r91b [M]: ss 0.1783, ss_rcw 0.1800, wcl 0.1666, wcl_rcw 0.1623, tt 0.1310, ff 0.0999, ff_rcb 0.0965,
ml 0.1387, ml_rcb 0.1182 ns (27,026 pins; 0 above 0.25).  Verdict on the tau9 copy: 247 gates, 205 PASS, 6 FAIL
(max_transition@ss, hold@wcl, lvs, drc, fresh_etm@ss,ml: the two test ETMs are now older than the PT results), 36 MISSING (ETMs of 7
corners, the 5 pnr gates, abstract, GDS chains: the copy has no GDS).

## A act noise state [M] (r91b copy, 9 corners; act = 4,608 ports, 9,216 load pins)
| corner | act pins analysed in detail | worst act bump above_low / below_high | act violators | all noise violators | undriven ports / pins | own act_o wire load p50 / max |
|---|---|---|---|---|---|---|
| ss | 0 | none recorded | 0 | 0 | 0 / 0 | 0.022 / 0.069 pF |
| ss_rcw | 0 | none recorded | 0 | 0 | 0 / 0 | 0.020 / 0.061 pF |
| wcl | 0 | none recorded | 0 | 0 | 0 / 0 | 0.022 / 0.069 pF |
| wcl_rcw | 0 | none recorded | 0 | 0 | 0 / 0 | 0.020 / 0.061 pF |
| tt | 0 | none recorded | 0 | 0 | 0 / 0 | 0.021 / 0.063 pF |
| ff | 2 | 0.156 / 0.270 V (U918/I) | 0 | 0 | 0 / 0 | 0.019 / 0.056 pF |
| ff_rcb | 10 | 0.161 / 0.317 V (U3854/I) | 0 | 0 | 0 / 0 | 0.021 / 0.063 pF |
| ml | 12 | 0.191 / 0.301 V (U3854/I) | 0 | 0 | 0 / 0 | 0.019 / 0.056 pF |
| ml_rcb | 34 | 0.189 / 0.324 V (U3854/I) | 0 | 0 | 0 / 0 | 0.021 / 0.063 pF |
- Timing state (R71) for comparison: PrimeTime has no driver model on act ("estimation failure default"); worst act bump 0.09 / 0.15 V
  at ml, 0.02 / 0.04 V at ss.  The noise state has "library set CCS noise iv curve" on every act port, noise_undriven_ports 0.
- "none recorded": in ss, ss_rcw, wcl, wcl_rcw, tt PrimeTime analyses no act net in detail in the noise state (NOISE-015 on act[3853],
  act[541]; the same after `update_timing -full` and with its SI filter ratios at 0), so there is no bump value in the decided state.
  ss, same session: timing state 98 pins analysed, worst 0.019 / 0.038 V; QB5_FT driver WITHOUT the port load 12 pins, worst 0.147 /
  0.281 V at U3854/I, 0 violators.  The wire load is what takes the act nets under PrimeTime's detailed-analysis threshold at the
  slow corners; the driver-only number is the upper bound available there.  Why the threshold falls where it does is not established
  (report header "Noise effort threshold : 0.20"; every analysed pin has a below_high bump >= 0.27 V at 1.1 V) [E].

## B tie cells [M] (r91b, tt SPEF + DEF; 146 TIEL + 1 TIEH hold 227 clock-gate TE pins and 1 flop E pin)
- Per tie net: fanout 1 / 1 / 3 (min / median / max), routed length 0.4 / 4.2 / 56.9 um, total capacitance 0.09 / 1.00 / 10.82 fF,
  coupling 0 / 0.32 / 2.87 fF, coupling / total 0 / 0.22 / 0.59 (worst optlc_net_2739: 3.1 um, 0.96 fF).  14 nets couple to a
  clock-network net (PrimeTime's 561 clock nets): at most 0.25 fF and at most 10 % of a net; 41 to a net of fanout >= 16: <= 0.75 fF.
- Kit [S]: liberty pin ZN / Z `driver_type pull_down / pull_up`, function 0 / 1, max_capacitance 0.0343 pF, no timing arc, no CCS-noise
  group, no I-V data; but `intrinsic_parasitic { intrinsic_resistance (VSS|VDD) { related_output; value } }` = the tie's resistance to
  its rail: TIEL 1.285 / TIEH 2.423 kohm (tc), 2.01 / 3.587 (wc), 1.126 / 2.099 (ml).  Databook: truth table, leakage, max cap only;
  the release note has nothing on ties; the kit's CeltIC .cdb noise libraries are not readable by PrimeTime.
- Gate (implemented, kit-derived): that resistance as the lib pin's steady-state resistance (PT man: for pins without library I-V
  data), then the normal noise analysis covers the tied pins; `noise_undriven_pins` proves no driver pin is left without a model.
  r91b, 9 corners: noise_undriven_pins 0 (check_noise "none" was 147 / 147), 143 - 190 of the 228 tied pins analysed in detail,
  worst bump 0.015 - 0.036 V (ml_rcb, a clock-gate TE pin), 0 violators.  act_blk / hub / top get the gate too and were not run.
- ICC2 Q-2019.12-SP2 man [S]: `opt.tie_cell.max_fanout` (default 999) bounds the fanout of tie cells inserted by optimisation; there is
  no tie distance option in this release (`opt.tie_cell.*` = max_fanout, add_to_highest_hierarchy; only the freeze-silicon command
  connect_freeze_silicon_tie_cells has -max_wire_length); length is bounded indirectly by the fanout limit and the 0.0343 pF max_capacitance.

## Q2 coverage / Q3 ETMs [M] (unchanged from the first report)
- PTE-003 = 910 arcs disabled by 147 tie cells (227 clock-gate TE low, 1 flop E high); UITE-416's 228 = those pins, now filtered from
  `$regs`; the 829 driverless nets have no load; 5 coverage gates, 0 in 9 corners.
- ETM: clock uncertainty is not in the model (identical .lib with / without it), the OCV derate is; the top applies each once.

## Hunks for files of other owners (not applied)
1. `signoff/pt/drv_eco.tcl` (ECO engineer), noise passes on the block's noise state:
   ```tcl
   # noise state of the block around a noise pass (R92; ::QB_PT_NOISE_STATE of the block script, the column's qb5_act_noise_driver):
   # on before fix_eco_drc -type noise, off = back to the timing state before any timing pass
   proc qb_eco_noise_state {mode} {
       set c [format {if {[info exists ::QB_PT_NOISE_STATE]} { puts "QB_ECO_NOISE_STATE %1$s: [{*}$::QB_PT_NOISE_STATE %1$s]"; update_timing; update_noise }} $mode]
       if {[info exists ::env(QB_ECO_CORNERS)]} { remote_execute $c } else { uplevel #0 $c }
   }
   ```
   and in `qb_eco_drc`, first and last statement of the `foreach ty $types` body:
   `if {$ty eq "noise"} { qb_eco_noise_state on }` ... `if {$ty eq "noise"} { qb_eco_noise_state off }`.
   qb_eco_state's noise count is taken in the timing state unless it is wrapped the same way.  After `off` the timing constraints are
   exactly the old ones; PrimeTime's incremental SI leaves <= 0.0002 ns on act_o transitions [M], far below QC_ECO_HOLD_MARGIN.
2. Step drivers: `cs=$(qb_corners) || exit 1` before the loops (a for list hides the status); last step `signoff/verdict.sh "$d"`.
3. ICC2 (P&R): `set_max_transition $::env(QC_CLK_TRAN_MAX) -clock_path [all_clocks]` per scenario; `opt.tie_cell.max_fanout` if a bound is wanted.

## Also found
- `qb_pt_si_checks` now gates `noise_undriven_pins` in every block's sign-off (act_blk, hub, top were not re-run): a macro or ETM pin
  without a noise model will fail there, which is the intended meaning of the gate.
- `signoff/pt/hub.tcl` 22 keeps a "no SPEF (dry run)" branch that can no longer pass qb_pt.  verdict.py repeats one criterion it cannot
  import (abstract.log: `QB_ICC2_DONE abstract`, no `^Error`).
- tau4's r91b changed under the verdict (a second ECO round, label eco2): its PT results are now older than the SPEFs and the verdict
  says so (`fresh_pt` FAIL in 9 corners).
- Left on the hosts: tau9 `/tmp/ckp908/qc18bacc/{f6,r92s}`, the r91b copy, `/tmp/ckp908/tools`; shared home `~/qb_r92`.
