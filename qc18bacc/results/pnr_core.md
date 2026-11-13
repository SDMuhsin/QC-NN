# qb_core alone through OpenROAD: routed area factor and routed fmax (R1 compute core)

Labels: **[S]** static: P&R geometry, PrimeTime (PT) with the def2spef SPEF, or OpenROAD's own estimate where marked
"OR est."; **[E]** estimate derived from [S] numbers.  Tool: OpenROAD 2.0-12381 (flow `flow/tsmc65/pnr`, unchanged) +
thin design scripts `qc18bacc/impl/pnr/` (below); PrimeTime Q-2019.12 with the def2spef SPEF.  Hosts: usask (full
core), tau5 (8 x 2 proxy); kit-derived views stay in `/tmp/ckp908/qc18bacc/build/pnr/<tag>`.

**Stop-rule status.**  Full `qb_core` (16 x 8): placed and clock-tree synthesised; global route **did not finish**
(33 min in FastRoute's congestion maze routing, 17.8 GB, stopped at the time box), detailed route **not attempted**
(~1.7 M instances after repair / CTS vs v4's 0.86 M, which peaked at 25.5 GB of the 30-GB hosts and took 7.6 h in
detailed route) -> its numbers are **post-CTS at OpenROAD's placement parasitic estimates** [S, OR est.].  To get a routed SPEF measurement within the box, the same netlist family and recipe was routed on the
8 x 2 configuration `qb_core_s` (16 PEs, 64 fused + 8 wide lanes; same RTL modules, DC per-element areas equal to
the full core, r1.md): detailed route converged (14 iterations, 58 DRC markers), PT tt / ss with SPEF.

## 1. Setup

| item | value |
|---|---|
| netlists | R1 DC runs unchanged: `qb_core_tt_p2.0` (usask) and `qb_core_s_tt_p2.0` (re-synthesised on tau5 with the same `impl/run.sh all qb_core_s 2.0`: identical area 921 629 um2, tt 500.4 / ss 316.6 MHz): tt compile, **2.0 ns (500 MHz)**, WLM WireAreaLowkCon enclosed, 20 % IO delay, max transition 0.2 ns, ports registered as in RTL (act / codes / params / lane stream all into or out of flops) |
| floorplan | no macros, square, core utilisation **0.60** of the DC cell area (`qb_core`: die 3006.8 x 3006.8 um; `qb_core_s`: 1259.4 x 1259.4 um), 10-um core margin, PDN flow default (M1 rails, M4 / M7 straps) |
| IO pins (29 502 on `qb_core`) | array side on the **left** (act 4 608, cd 2 304, ctl, t2 1 088, clk, rst_n); **top** b2 / b2_vld (1 025); **right** = every lane-side bus (pf 5 189, pw 5 059, s_rd 4 352, w_r, f_y 4 352, f_b, w_y, w_b, PPU controls; 20 465 pins on M3 / M5 / M7).  Positions within a side by `place_pins` after a skip-IO global placement (`io_place.tcl`, as ORFS) |
| P&R corners | **tt only** for DRV repair / CTS / estimates (`core.cfg`): with ss tt ff the DRV repair fixes the 0.2-ns max transition at ss, which the tt-compiled netlist never met (`qb_core_s`: +37 % cell area, utilisation 0.60 -> 0.825, detailed placement stalled).  Sign-off timing tt **and** ss by PT with the routed SPEF |
| recipe (v4 lessons applied) | gpl 512 x 512 bins, target density 0.70, no padding, not timing / routability driven (v2-v4: diverged / no gain; run time); DRV repair of violating nets only (`REPAIR_DESIGN auto`), then **incremental gpl + second DRV repair** (`gpl_incr.tcl`, v4 mechanism 4); CTS `-balance_levels -sink_clustering_buffer CKBD4` (1 803 DC clock gates); no timing repair, no hold repair, no antenna repair (segfaults in this build) |
| `qb_core` after CTS | DRV repair of the violating nets + legalisation (300-um window) again (`grt_est.tcl`, the v3 `QA_DRV_POST` lesson), then reports at placement estimates; global route at `GR_ADJUST` 0.25 |
| `qb_core_s` route | flow `route` step (global route, detailed route 14 iterations, fillers / decaps), def2spef tt / ss, PT (`pt_post_core.tcl`, `pt_diag.tcl`) |

## 2. Results

| quantity | `qb_core` 16 x 8 (full) | `qb_core_s` 8 x 2 (proxy) | label |
|---|---|---|---|
| DC cell area (WLM) | 5.353 mm2 (1 373 100 cells, 205 020 flops) | 0.922 mm2 (243 410 cells) | [S] |
| die / core area | **9.041 / 8.914 mm2** | **1.586 / 1.535 mm2** | [S] |
| cell area after place / CTS (x DC) | 7.252 (x1.355) / 7.550 (x1.410); + post-CTS DRV 7.688 (**x1.436**) | 1.040 (x1.128) / 1.076 (**x1.168**) = routed | [S] |
| P&R buffers (place-step DRV repairs) | 163 535 (113 311 + 50 224) | 7 649 (5 565 + 2 084) | [S] |
| utilisation (core) | 0.81 place, **0.86** after CTS + DRV | 0.68 place, **0.70** routed | [S] |
| routed factor = core / DC | 1.665 (set by the floorplan; **infeasible-dense**: 0.86 utilisation, see 3.3) | **1.665, routes** (die / DC 1.72) | [S] |
| detailed route / DRC markers | not run (stop rule) | 14 iterations (88 k -> 13 k -> 845 -> 58), **58** (54 cut spacing, 4 metal spacing); antennas not checked | [S] |
| total wire / vias | | 8.88 m / 2.06 M | [S] |
| pre-route fmax tt / ss (DC netlist, PT, WLM, ideal clock) | 500.4 / 314.9 MHz (r1.md) | 500.4 / 316.6 MHz | [S] |
| **post-route fmax reg2reg tt / ss** (PT + SPEF, propagated clock) | post-CTS OR est. tt **100.9 MHz** (WNS -7.913 ns); ss not estimated (P&R corner tt) | **322.5 / 201.5 MHz** (WNS -1.100 / -2.963 ns) | [S] / [S, OR est.] |
| routed / pre-route tt fmax | x0.20 (post-CTS est.) | **x0.64** (ss x0.64) | [S] |
| worst path without repeater chains (proxy) / worst per block class (full) | post-CTS OR est.: worst PE-class path 172.3 MHz (-3.804), wide lane 144.5 (-4.92) | tt **415.4 MHz** (PE S0 code reg -> popcount -> s reg, -0.407); ss 249.3 (wide lane `sh1 -> y2`) | [S] |
| critical path (tt) | fused lane `g_fq_0__g_fc_4__g_fi_7__u_lf/u_rlate/q_reg_2_ -> u_rout/q_reg_0_` | fused lane `g_fi_6__u_lf/u_rlate/q_reg_2_ -> u_rout/q_reg_0_` (also ss) | [S] |
| hold, no hold repair (tt) | post-CTS OR est.: reg2reg -0.546 ns, incl. IO -1.689 ns | PT tt reg2reg **-0.012**, incl. IO -0.394 (9 893 endpoints, worst `pf[1119] -> u_pbf/p0`); ss reg2reg +0.013, IO -0.785 | [S] |
| clock tree worst latency / skew (tt) | 2.06 / 0.73 ns (OR est.) | 0.74 / 0.09 ns (PT) | [S] |
| violating reg2reg endpoints at 2.0 ns tt | | 2 768, of which 1 288 through P&R repeater chains | [S] |
| peak RSS / wall | place + CTS 10.8 GB, 31.5 min (from pdn) | 16.4 GB, 63 min (place .. finish) | [S] |

### 2.1 Estimates vs routed SPEF

The full-core global route (from the post-CTS DRV-repaired checkpoint `db/cts_drv.odb`, `GR_ADJUST` 0.25, 50
congestion iterations) was still in maze routing after 33 min and was stopped: no post-GRT numbers.  A maze phase
that long on a 0.86-utilisation placement is itself a congestion indication (the proxy at 0.70 global-routed in
~3 min).  Calibration of the estimates on the proxy (same lane path in every stage, tt WNS): OR est. place -0.965, post-CTS
-0.977, post-GRT -1.211 ns vs **PT + SPEF -1.100 ns**: the OpenROAD estimates bracket the routed number within
0.12 ns, so the full-core estimates are not an RC-model artefact.

## 3. What limits the routed fmax (mechanism)

### 3.1 Wire share on the critical paths [S]

`wire_share.py` splits the data path of a report with input-pin rows into net (RC) delay, cells inserted by the P&R
repair (repeaters `wireN` / `splitN`) and logic cells; `pt_diag.tcl` re-times the same path in PT with the
parasitics removed (zero wire), so (routed - zero-wire) / routed also counts the cell delay that the wire
capacitance adds.

| path (`qb_core_s`, PT + SPEF) | data path | logic cells | P&R repeaters | net RC | wire share: zero-wire comparison | label |
|---|---|---|---|---|---|---|
| tt critical: fused lane `u_rlate -> u_rout` | 2.93 ns (71 stages) | 1.82 ns | **1.06 ns (34 buffers)** | 0.05 ns | 21.7 % on top of the repeaters (zero wire 2.217 ns incl. the 34 repeaters) | [S] |
| ss critical: same lane | 4.66 ns | 3.12 | 1.49 | 0.05 | 24.2 % (+ repeaters) | [S] |
| tt worst without repeaters: PE `u_in/c_q -> u_pop/s_q` | 2.11 ns (20 stages) | 2.05 | 0 | 0.06 | **22.6 %** (zero wire 1.656 ns) | [S] |
| ss worst without repeaters: wide lane `sh1 -> y2` | 3.64 ns (40 stages) | 3.62 | 0 | 0.02 | **43.2 %** (zero wire 2.095 ns) | [S] |

Wire-attributable share of the tt critical path [E]: repeaters 36 % + wire load on the other cells ~22 %, i.e.
roughly half of the 2.93 ns; the logic alone (zero wire, repeaters removed) is ~1.5 ns, inside the 1.75-ns budget.
Net RC itself is negligible (1-3 %) everywhere: the wire costs through the **capacitance it puts on DC-sized drivers**
and through **repeater chains**, not through RC delay.

### 3.2 Mechanism of the critical path (proxy, routed)

The fused lane `g_fi_6` is stretched over ~540 um: its head (`u_rlate` late-operand register, operand select) at
x ~685 um, y ~155 um, its adder / round tail and `u_rout` at x 1 100-1 225 um next to the right-edge f_y pins
(placement checkpoint, `locq` query).  The place-step DRV repair buffered the long net with a 34-buffer chain at the
global-placement positions; the incremental global placement then moved the endpoints and the chain was left clumped
at x 530-570 um (30 buffers within ~40 um, then a 530-um jump), i.e. the repeaters add ~1 ns without covering the
distance (the v4 "repair buffers left off their wires" effect, which the second DRV repair does not undo).
Lanes sit between two pulls: the PE shadow outputs (array, left / centre) and the lane-stream pins on the right
edge; the non-timing-driven placement lets one lane span that distance.  Of the 2 768 violating endpoints at 2.0 ns,
1 288 go through such repeater chains; without them the worst path is the PE popcount path at **415 MHz tt**
(0.4 ns over: 22.6 % of its delay is wire load: the S0 code register `c_q[64]` drives fanout 9, and the popcount
tree nets), and at ss the wide-lane 20 x 31 multiplier path (249 MHz, 43 % wire load: the 32 wide lanes are fed
through the lane-serial chain and spread).

### 3.3 Full core: the same mechanism, much stronger (post-CTS OR est.)

* Area: the place-step DRV repairs inserted 163.5 k buffers (21x the proxy for 5.8x the cells; 18.7 k + 16.3 k nets
  over the max wire length) and the cell area grew x1.44 (proxy x1.17): the 3-mm die makes the PE-to-lane drains, the broadcast and
  the pin-to-register wires long.  At core / DC 1.665 this ends at **0.86 utilisation**, where legalisation moves
  cells up to 267 um (HPWL +9 %; with the default window detailed placement failed, DPL-0036) and re-creates long
  D0 / D1-driven nets after every repair.
* Timing: every class is dominated by slew on DC-sized D0 / D1 drivers carrying long wires, not by logic depth:
  PE class worst `g_r_13__g_c_2__u_pe/u_in/c_q_reg_239_ -> u_pop/s_q_reg_19_` 5.53 ns data path vs <= 1.75 ns in DC
  (DFQD1 Q 0.150 pF fanout 9, AOI22D0 0.104 pF slew 2.09 ns, INVD1 0.137 pF); fused lane 9.63 ns (NR2D0 / AOI22D0 /
  CKND2D0 stages at 0.4-0.7 ns each); wide lane 6.56 ns.  Net RC is 1.7-2.5 % of these paths; by comparison with the
  DC path (<= 1.75 ns), >= 80 % of the post-CTS delay is wire-load-induced [E].
* Clock: 205 k flops on a 3-mm die, tree latency 2.06 ns, skew 0.73 ns (proxy 0.74 / 0.09).

## 4. Conclusions for the area / clock model

1. **Routed factor.**  At core / DC = 1.665 the 8 x 2 proxy routes (0.70 utilisation, 58 DRC) with cells x1.17; the
   full 16 x 8 core at the same factor ends at 0.86 utilisation with cells x1.44, which this recipe cannot legalise
   cleanly.  Keeping the full core at ~0.70 utilisation needs core / DC ~ 1.44 / 0.70 = **~2.05** [E] (vs the PI's
   logic x1.7 and the v4 measured 1.71 cells / DC at 0.67).
2. **Routed fmax.**  Proxy, routed + SPEF: **322.5 MHz tt / 201.5 MHz ss** (x0.64 of pre-route, same ratio as v2-v4);
   415 MHz tt if the repeater-chain lanes were placed compactly.  Full core post-CTS est.: ~100 MHz tt, i.e. the
   standalone 3-mm placement of this recipe does not produce a usable core; the limiter is placement locality
   (lane / PE cells spread, DC-sized drivers on long wires, clumped repair chains), not RC and not logic depth.
3. **Fixes worth testing next** (not done, time box): timing-driven or region-constrained placement of each PE row /
   lane group (as v4's structured crossbar placement), a `repair_timing -setup` pass after CTS (removes / rebuffers
   the chains), resynthesis with DC topographical or ss-aware DRV so the P&R repair does not grow the area x1.4, and a
   lower start utilisation (~0.5) for the full core.

## 5. Files and commands

Scripts (new, `qc18bacc/impl/pnr/`): `core.cfg` (design config for `flow/tsmc65/pnr/run_pnr.sh`), `pins.tcl`
(floorplan-time ordered pins), `io_place.tcl` (skip-IO gpl + side-constrained pins), `gpl_incr.tcl` (incremental gpl
+ second DRV repair), `grt_est.tcl` (post-CTS DRV repair, post-CTS / post-GRT reports at estimates, per-class worst
endpoints), `pt_post_core.tcl` + `pt_diag.tcl` (PT with SPEF: fmax lines, repeater classification, zero-wire
re-timing), `wire_share.py` (net / repeater / logic split), `run.sh`.

```bash
# on the host, in /tmp/$USER/qc18bacc/repo (synthesis under $QC_BUILD/syn):
QC_PNR_TO=cts QC_PNR_POST=0 qc18bacc/impl/pnr/run.sh pnr qbc_p1        # qb_core: floorplan .. CTS
qc18bacc/impl/pnr/run.sh est qbc_p1                                     # post-CTS DRV repair, est. reports, GRT
QB_TOP=qb_core_s QB_DR_ITER=14 qc18bacc/impl/pnr/run.sh pnr qbs_p1      # proxy: full flow incl. route + tt SPEF
qc18bacc/impl/pnr/run.sh spef qbs_p1 && QB_PT_DIAG=1 qc18bacc/impl/pnr/run.sh pt qbs_p1
python3 qc18bacc/impl/pnr/wire_share.py <pnr dir>/rpt/pt_post_tt_reg2reg.rpt
```
