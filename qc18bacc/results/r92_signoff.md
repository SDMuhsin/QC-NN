# R92 (sign-off half): gates that fail on evidence, one machine verdict, coverage / SI / ETM answers

Evidence: r91b (FAILED sign-off) and r87 on tau4, read only; PrimeTime Q-2019.12-SP2 on a copy of r91b on tau9 (no GDS / nlib; scratch
`/tmp/ckp908/qc18bacc/r92s`).  [M] measured, [S] read from source, [E] estimate.  Nothing committed; no Calibre / ICC2 run by this task.

## Status
- F1 - F6 fixed and verified [M]; Q1 - Q3 answered by tool checks [M]; the Q2 gates ran in all 9 corners.  Not applied: the hunks for
  other owners' files (end).  Q1's driver model is a proposal, measured at ml and ss only.
- r91b re-timed with the R92 scripts is still NOT signed off: wcl hold 2, ss max_transition 6 (+ its Calibre reports: LVS INCORRECT,
  4 DRC results).  The new gates add no violator: clock transition and coverage are 0 in every corner.

## Changes (worktree, uncommitted; the 8 flow files are md5-equal in tau9 `f6` and in `~/qb_r92`, the copy tau4 read)
- F1 `signoff/calibre/cal.sh`: `cal_result <mode> <top> <rundir>` judges a finished run from its files (LVS: report not older than its deck,
  overall + top-cell row CORRECT, no INCORRECT / NOT COMPARED row; DRC / antenna: the deck's summary report, of this top, not older, TOTAL 0,
  every QB_ rule run).  drc / ant / lvs end with it (exit 1 on FAIL, CAL36 lines kept); `cal.sh check <mode> <top> <rundir>` = no Calibre.
- F2 `common/eco_changes.tcl`: `qb_eco_loads` = leaf input pins + output ports, error if none; every {name ref x y layer} buffer of
  `add_buffer_on_route` parsed (`abor {pin cell ref [cell ref ...]}`), any other token count = unparsed.
- F3 `common/env.sh`: `qb_corners` returns 1 + `QB_FAIL` (stderr) on a site.tcl error or an empty list.  `qb_pt` also fails without PT's
  completion line, with a "Diagnostics summary" error, with 0 annotated coupling capacitances, or with `^Error` in a DMSA worker log;
  `PT_ERRORS` ends `signoff_fails N evidence ok|bad`; `qb_pt -check <log>` = the gate on a finished run (`<log>.time`).
- F4 `common/env.sh` exports `QC_CLK_TRAN_MAX` (0.25) and `QC_ECO_HOLD_MARGIN` (0.005), overridable.  `signoff/pt/common.tcl` applies
  `set_max_transition $QC_CLK_TRAN_MAX -clock_path [all_clocks]` when sourced (sign-off scripts and the DMSA ECO setup); `qb_pt_drv`
  splits violators into data / clock-network pins, QB_PT_SIGNOFF gets `clock_max_transition N`.
- F5 `signoff/verdict.sh <run dir> [top]` + `verdict.py`: `GATE <name> <corner|-> PASS|FAIL|MISSING <evidence>` lines, a `VERDICT` line
  naming the FAIL (violation or stale file) and MISSING (evidence never produced) gates, last line `SIGNOFF <top> PASS|FAIL`, exit status
  accordingly.  215 gates for the column: per corner pt_log (qb_pt -check), 14 QB_PT_SIGNOFF counts, annotation, dont_use, etm_log, etmcheck,
  fresh_spef / _pt / _etm; block: dont_use_icc2, eco_names per round, abstract x 6, lvs / drc / antenna (cal.sh check), drc_qb_rules, 6 chains.
- F6 `common/lib_cells.tcl` `qb_lib_tcq`: the cache file stores its key (liberty size + mtime, QC_DONT_USE, text of lib_tcq.py); another
  key or the old format is recomputed (~35 s per library [E], so the cache stays).
- Q2 `signoff/pt/common.tcl` `qb_pt_coverage`, called by `col_blk.tcl`, which also drops the tie-constant pins from `$regs`.

## Verification [M]
| item | test | result |
|---|---|---|
| F1 | `cal.sh check`, tau4 reports | r91b: lvs FAIL (INCORRECT), drc FAIL (4 results, 3 rules), ant PASS; r87: 3 x PASS; no dir / wrong top: FAIL |
| F2 | PT on r91b | U_PTECO_DRC_BUF20 loads `{b2[102]}` (was `{}`); 81 / 81 new cells have loads; 2-buffer line -> 2 cells; 4-token list -> unparsed; dangling buffer -> error |
| F3a | fake site.tcl | error / empty list: status 1 + QB_FAIL; real table: 9 corners, status 0 |
| F3b | copies of pt_blk_ss.log | no completion line, empty or missing parasitics log, `Error` in a worker out.log, no .time, diagnostics error: each `evidence bad`; intact log and r91b's pt_eco.log (9 worker reads): `evidence ok` |
| F4 | r91b, 9 corners; ss with the limit at 0.15 | clock_max_transition 0 everywhere at 0.25, worst transitions below; at 0.15 the gate fires: 8,615 clock-network + 6 data violators (first try mis-split 1 pin: regexp fixed, re-run) |
| F5 | tau4, runs as they stand | r91b FAIL `max_transition@ss hold@wcl lvs drc`; r87 FAIL `noise@ml,ml_rcb` |
| F6 | PT on tau9 | old-format cache recomputed and rewritten with its key, value unchanged (0.07939 ns, SDFQND1) |

Worst clock-network transition, r91b, PT with SI, 27,026 clock-network pins [M]: ss 0.1783, ss_rcw 0.1800, wcl 0.1666, wcl_rcw 0.1623,
tt 0.1310, ff 0.0999, ff_rcb 0.0965, ml 0.1387, ml_rcb 0.1182 ns.  At ss 8,632 pins exceed the 0.15 ns CTS target (p50 0.138, p99
0.164); the brief's 111 pins from ICC2's extract_drv.rpt were not re-read; PT's values include the crosstalk delta transition.
Verdict, tau4, old logs: r91b 124 PASS / 4 FAIL / 87 MISSING; r87 131 / 2 / 82.  MISSING in both: clock_max_transition and the 5 coverage
counts x 9 (logs predate R92), the 3 ETM gates x 9 (post stopped first); r91b also the 6 abstract gates (views never ran); r87 also
eco_names (label eco, no "eco names" line: older than the R90 gate).  Verdict, tau9 copy after the R92 PT re-run + ETMs of ss and ml: 180
PASS, the same 4 FAIL, 31 MISSING (ETM gates of 7 corners, abstract, 4 GDS-chain gates: no GDS in the copy; they PASS on tau4).  The ss
ETM is identical with and without the clock limit (0 differing lines).

## Q1 SI / noise on port-driven nets [M]
- act (4,608 ports, driving cell removed): no holding-driver model.  report_noise_calculation: "Steady state resistance source: estimation
  failure default"; crosstalk report: act victims / aggressors "No Lib Cell"; check_timing: "4608 ports with parasitics but with no driving
  cell".  The other 2,350 inputs keep BUFFD4/Z (victim driver "BUFFD4"; with a cell the source is "library set CCS noise iv curve").
- Proposed driver model P1: QB5_FT as the act driving cell, driven with the block's own QB5_FT input slew of the bit, port load = the previous
  column's act_o wire (own act_o[b] net, p50 0.019 pF).  It reproduces the measured act_o transition: P1 - flow -15 .. +9 ps (ml), -10 .. +8 ps (ss).

| corner | state | setup act2reg | setup act2act_o | hold act2reg | hold act2act_o | worst act bump, above_low / below_high | noise violators |
|---|---|---|---|---|---|---|---|
| ml | flow | 2.4558 | 0.2557 | 0.0006 | 0.0207 | 0.09 / 0.15 V | 0 |
| ml | P1 | 2.4611 | 0.2610 | 0.0279 | 0.0559 | 0.19 / 0.30 V | 0 |
| ss | flow | 2.3490 | 0.0879 | 0.0002 | 0.0623 | 0.02 / 0.04 V | 0 |
| ss | P1 | 2.2860 | 0.0465 | 0.0423 | 0.1121 | 0.15 / 0.30 V (BUFFD4 cell without the wire load; not read for P1) | 0 |

- The flow under-states the act noise bumps 2 - 7x (no violator with the real driver either) and over-states the crosstalk delta delay
  (act[541] max rise 0.060 -> 0.036 ns at ml, 0.115 -> 0.072 ns at ss, BUFFD4 cell).  P1 cannot replace the timing state: PrimeTime adds
  the driving cell's load-dependent delay at the port (288 sampled bits: min path 0.016 - 0.038 ns at ml, 0.037 - 0.089 ns at ss; max path
  0.018 - 0.042 / 0.041 - 0.099 ns), which the upstream column's act -> act_o path already contains (R71): hold would look 27 - 50 ps
  better than it is.  Proposal: timing stays on the R71 state, the noise gate (and the ECO's noise passes) run on P1 (hunk 3).  Noise
  with P1 was run at ml and ss only, not yet in the other 7 corners.

## Q2 Coverage [M] (identical in the 9 corners)
- PTE-003: 910 disabled arcs, all constant propagation from 146 TIEL + 1 TIEH (flags p 456, C 454; none loop-breaking, user or case):
  227 clock gates CKLNQD* with TE tied low (2 CP->TE checks + 2 TE-conditioned CP->Q arcs each) + EDFQD2 u_lw/m0_reg_21_ with E tied high
  (CP->E setup + hold).  UITE-416, 228 invalid end points: those 227 TE pins + 1 E pin, members of `all_registers -data_pins`, given as
  `-to $regs` by two path queries; col_blk.tcl filters them: 0 such warnings in the 9 new logs.
- "driverless 829": of 240,808 nets 239,979 have a driver, 239,802 a load, 0 a load and no driver; the 829 have neither (dangling bus bits of the flattened netlist: u_lf 579, u_pe acc 196, u_lw 54); loadless 177 = SYNOPSYS_UNCONNECTED outputs.
- New gates, 0 in all 9 corners: unconstrained_endpoints, unclocked_register_pins (of 26,132), loops (check_timing + flags l / L),
  unexpected_disabled_arcs (flag p / C on a cell with an input on a tie-cell net; every constant pin a tie output or such an input: 147 +
  228, 0 stray), floating_nets.  Expected sets come from the netlist; unannotated_pin_to_pin stays.

## Q3 ETMs [M] (extract_model at ss, twice in one session)
- Clock uncertainty is NOT in the ETM: the .lib extracted with and without `set_clock_uncertainty` are identical (0 differing lines, 39.9
  MB).  cd[110] setup arc at the context slews (0.5 / 0.5 ns): 2.2459 ns; block path data 2.9433 - clock 0.6555 - 0.0184 = 2.2694 ns
  without the 0.25 (2.5194 with it).  The OCV derate IS in the arcs: that path is timed with data x1.05 / clock x0.95 (0.1747 ns of the
  arc), and extract_model writes `<etm>_constr.pt`: derate 1.0 for -cell_check / -cell_delay, 0.0 -increment on the instance.
- The top: `set_clock_uncertainty 0.25 / 0.05` (blocks/top/pt_sdc.tcl) is the only place interface paths get it: keep it, never add it to
  the ETM context.  top_chip.tcl sets the ETM instances' cell-delay derate to 1.0 and has no cell-check or incremental derate (= the
  _constr.pt); top nets keep 1.05 / 0.95.  Each is counted once: no change needed.

## Hunks for files of other owners (not applied)
1. Step drivers (`blocks/col/run.sh` 78 / 88 / 93 / 100, `blocks/top/run.sh` 42 / 73 / 77, `common/status.sh` 22): a for list hides
   qb_corners' status [M: 0 iterations].  `cs=$(qb_corners) || exit 1` once, then `for c in $cs`, `QB_ECO_CORNERS="$cs"`; last step
   `bash "$QBF/signoff/verdict.sh" "$d" || exit 1`.
2. `icc2/common.tcl` qb_eco_names, abor case (only the first buffer of a multi-buffer line is checked today); drv_eco.tcl needs no hunk
   (it goes through qb_eco_loads, a worker error now fails qb_pt); an old `pt_eco_cells.txt` with `{}` mismatches until PT rewrites it:
   `abor { lappend want pin [lindex $f 0]; foreach {c r} [lrange $f 1 end] { lappend want abor $c ref [list $c $r] } }`
3. `blocks/col/io_budget.tcl`, new proc (the P1 state as measured).  col_blk.tcl calls it after the last timing report, before
   qb_pt_si_checks (my file; not added while the proc does not exist); the ECO's noise passes need it too, then qb5_act_tran_apply:
   ```tcl
   proc qb5_act_noise_driver {} {   ;# R92: holding driver of act for the noise analysis only (not timing: R71 double count)
       foreach_in_collection p [get_ports {act[*]}] {
           regexp {\[(\d+)\]$} [get_object_name $p] -> b; set on [get_nets -of_objects [get_ports "act_o\[$b\]"]]
           set fi [get_pins -of_objects [get_cells -of_objects [get_pins -leaf -of_objects $on -filter "direction==out"]] -filter "direction==in"]
           lappend plan $p [get_attribute $fi actual_rise_transition_max] [get_attribute $fi actual_fall_transition_max] \
               [expr {[get_attribute $on total_capacitance_max] - [get_attribute [get_nets -of_objects $p] total_capacitance_max]}] }
       foreach {p r f cw} $plan { set_load $cw $p
           set_driving_cell -lib_cell [lindex $::QB5_FT 0] -pin [lindex $::QB5_FT 1] -input_transition_rise $r -input_transition_fall $f -no_design_rule $p }
   }
   ```
4. ICC2 (P&R): `set_max_transition $::env(QC_CLK_TRAN_MAX) -clock_path [all_clocks]` per scenario; the ECO reads `QC_ECO_HOLD_MARGIN`.

## Also found
- The 147 tie-cell outputs are check_noise's only "none" drivers: "noise 0" is not evidence for the 227 clock-gate TE pins.  Not fixed.
- `signoff/pt/hub.tcl` 22 keeps a "no SPEF (dry run)" branch; such a run can no longer pass qb_pt (0 coupling).  Only the column prints
  QB_PT_SIGNOFF setup / hold / DRV / coverage; act_blk.tcl, hub.tcl, top_chip.tcl get the clock limit now but were not re-run here.
- The 6 ss max_transition violators are 0.50x ns against 0.50, all in u_pe g_r_4 g_pop2_u_acc.  verdict.py repeats one criterion it
  cannot import: abstract.log needs `QB_ICC2_DONE abstract` and no `^Error` (qb_icc2 has no check mode).
- Left on the hosts: tau9 `/tmp/ckp908/qc18bacc/{f6,r92s}`, the r91b copy (PT results = the R92 re-run), `/tmp/ckp908/tools`; home `~/qb_r92`.
