# R94: column runs on one frozen commit; the eco interface bug; the pre-ECO baseline (Nov 26, 21:00-23:45 UTC)

[M] measured, [S] read from source or man page, [E] estimate.

## Provenance
- main = 318b778, which is 7d682b3 plus the one-thread DEF write (below).
- The flow ran from an immutable snapshot of that commit, /tmp/ckp908/qc18bacc/f7, on tau8, tau10 and tau11:
  - VERSION 318b778 and MANIFEST.md5 covering 240 files [M]; the manifest verified intact at 22:10.
  - site.tcl md5 is 9c3c1428b435 on all three hosts.
- Runs:
  - **r94 (tau10):** P&R up to route ran on ca34203, so the run is MIXED. From outputs onward it ran on f7: a
    diagnostic of the committed eco -> sign-off chain.
  - **r96 (tau8):** from scratch, no P&R guard-band.
  - **r97 (tau11):** from scratch, QC_PNR_GUARD_HOLD 0.010 and QC_PNR_GUARD_TRAN 0.05: an A/B test of the measured
    at-limit populations.
  - Steps for r96 and r97: pnr, eco, calibre, post, views, signoff.

## write_def segfault (tool defect)
- **[M] The crash:** ICC2 Q-2019.12-SP2 died with signal 11 in write_def. Both times the fault was in a worker thread
  at the same frame (0x1f20132) while the main thread waited to join it. This happened in 2 of 2 sessions on r94's
  route label at 16 cores. At 1 core the same step was clean (48 s), and r95 was clean at 16 cores.
- **318b778:** icc2/outputs.tcl now writes the DEF with `set_host_options -max_cores 1`, then restores QB_ICC2_CORES.
  - [M] r94 outputs at 16 cores with this change: rc 0, 48 s; portcheck OK; Calibre fill / odpo rc 0.

## r94 pre-ECO sign-off (route label)
- **Calibre:** LVS CORRECT; DRC 0 results (1572 rule checks, QB gate rules 1); antenna 0 [M].
- **PrimeTime post:** FAIL. The evidence is clean in all 9 corners (rc 0, worker_errors 0, coupling annotated).
  Non-zero QB_PT_SIGNOFF counts [M]:

| corner | counts |
|---|---|
| ss | hold 2, max_transition 57, max_capacitance 4 |
| wcl | setup 16, hold 4, max_transition 27 |
| tt | max_capacitance 1 |
| ff | hold 6 |
| ff_rcb | hold 6, max_capacitance 3 |
| ml | hold 12 |
| ml_rcb | hold 6, max_capacitance 1, noise 4 |
| ss_rcw, wcl_rcw | clean |

- **Total 149:** hold 36, max_transition 84, max_capacitance 9, setup 16, noise 4. This is the same number as eco
  round 1's prefix_total, so the ECO's PrimeTime view agrees with sign-off.

## Eco round 1 (the committed loop)
- **PrimeTime DMSA [M]:** worker_errors 0; coupling 19.6M annotated in 9 reads; prefix_total 149. Change list: 919
  lines (518 insert_buffer, 99 add_buffer_on_route, 98 size_cell, 197 set_cell_location).
- **ICC2 FAILED after 35 s:**
  - At `pt_eco.tcl:36`, `add_buffer_on_route [get_net -of {ropt_h_inst_18992/Z}] -user_specified_buffers {
    U_PTECO_HOLD_BUF18 BUFFD1 247.200 101.300 0} -no_legalize` raised UIED-333 "Can not find unique layer to insert
    buffer near given location".
  - UIED-309 and UIED-180 followed, then a Tcl error.
- **Mechanism [M]** (replayed on a scratch copy):
  - 96 of the 99 add_buffer_on_route buffers give the projection of the new cell's centre onto the nearest wire of the
    net, plus that wire's layer.
  - Three buffers (lines 36, 52, 76) give layer `0` and the cell centre, which is off the route. All three sit next to
    a corner where the route changes layer.
  - ICC2 treats `0` like -detect_layer and snaps to the nearest wire. At line 36 an M6 wire and an M5 wire are equally
    near (1.450 um edge distance), so it raises UIED-333.
  - Controls: the same command with M5 or M6 inserts cleanly.
  - No earlier line in the list touches that net.
- **[S] No PrimeTime option for it:** write_changes has only -format, -output and -reset, and its man-page example
  writes layer 0.
- **Fix: commit 55b91cf** on branch worktree-agent-a9972a467ce9eb0c4, NOT on main.
  - qb_eco_route_layers / qb_eco_route_point (icc2/common.tcl) and qb_eco_abor (common/eco_changes.tcl).
  - eco.tcl sources out/eco/<label>/pt_eco_resolved.tcl.
  - Each layer-0 buffer gets PrimeTime's own rule: the projection onto the nearest wire centreline.
  - An exact tie goes to the lower LEF layer, then the lower x, then the lower y.
  - It fails on a net without wires, an unparsed line, or a non-routing layer.
- **Replay of the complete ICC2 eco step** on a copy of r94 with the fix [M]:
  - rc 0, errors 0, tool_errors 0, wall 11:09.
  - Line 36 -> M5 (a tie), line 52 -> M3, line 76 -> M2. The other 916 lines are byte-identical.
  - Names gate: 617 new cells, 0 missing.
  - Legality: 0 violations.
  - Route gate PASS: drc 0, open 0, antenna 0; check_lvs short / open / floating 0; 0 closure passes.
  - Negative test: a layer-0 buffer on a net without wires fails with the resolver's message.
  - ICC2's own post-ECO timing, NOT sign-off: hold 26 endpoints at -0.00 ns (17 of them at wcl), setup +0.07, one
    max_capacitance pin at its limit. This is the at-limit population again; the next PrimeTime round judges it.

## Sign-off gates: commit a059534 on branch worktree-agent-a02583c9d3999ab49, NOT on main
- **LVS ERC gate** (`cal.sh cal_result erc`, `verdict.py` lvs_erc), with `signoff/calibre/erc_allow.txt`:
  - 6 inductor checks may be NOT EXECUTED, and only while their marker layers are empty;
  - [M] 10 seeded faults all FAIL, and r91b passes.
- **clk_lat:**
  - only sign-off sessions write out/clk_lat_<c>.txt; setup-only sessions leave it alone [M];
  - verdict gate: the file must equal the logged value. A wrong value FAILs and a missing file is MISSING [M].
- **Recovery / removal** counted in QB_PT_SIGNOFF and the verdict.
  - [M] The column has 0 async pins.
  - Its 227 clock-gating checks were already inside the setup / hold counts.
- **r91b under the new verdict:** 192 pass, 2 FAIL (max_transition@ss, noise@ml_rcb), 83 MISSING. The MISSING come
  from old-format logs; re-running post clears them.

## Fresh hunts on 318b778 (round 3)
13 confirmed: 11 new and 2 re-finds of round 2 (the ECO noise state; ERC not read).

New, sign-off side:
- cal.sh:54: a QB_ rule that was NOT EXECUTED passes its gate.
- outputs.tcl writes label.txt before portcheck / fill run, so an eco retry can time a new netlist against stale SPEFs.
- act / hub / top PrimeTime scripts print no QB_PT_SIGNOFF setup / hold / DRV line, so violations never fail them.
- verdict.py gates every "eco names" line ever written, so an old FAIL line fails a clean re-run.

New, P&R side:
- The act hold budget QC_ACT_HOLD_HUB is assumed by the column but not enforced by act or hub.
- act post drops PrimeTime / ETM failures.
- top pt / views / dr can run with an empty corner list.
- hub signoff drops fin's status.
- top fp passes the PG check when none ran.
- The lib_pincap cache is never invalidated.
- The qb_ndm key misses QC_PNR_DIODE and the ICC2 binary, and a half-written NDM library is reused.

Suspicion [M]: on r94, the SPEF is 1.7-1.8 % larger at 16 cores than at 1 core, for the same label and fill.

## Hub r92f (tau2)
- It ran the hub agent's forked driver on an old base. Killed 21:55: closure pass 1 left 26,619 DRC (short 11,646,
  min edge length 8,611, min area 4,931, diff-net spacing 1,335; tracks ok).
- That signature needs location binning when the hub moves to the shared driver.
