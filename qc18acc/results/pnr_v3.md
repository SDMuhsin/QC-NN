# QC18-ACC v3 place & route (OpenROAD), improvement study, post-route timing / power / GLS

Inputs: DC netlist `qa3_w3.3` (v3, Kb = 2, WLM, 3.3 ns at ss; pre-route PT: ss 303.2 / tt 463.4 MHz, 6.514 mm2,
816.4 kGE logic, 336.2 mW = 68.5 uJ / inference at 400 MHz tt, [v3.md](v3.md)) and, for the comparison, the v2
routed run `qa_t1` of [pnr.md](pnr.md).  Tool: OpenROAD 2.0-12381, flow `flow/tsmc65/pnr` (unchanged) + design
configs `qc18acc/pnr/` (`qa3.cfg`, `qa3b.cfg`, `macro_place3.tcl`, the optional settings of `post_cts.tcl` /
`post_grt.tcl`); PrimeTime / PTPX Q-2019.12 with the def2spef SPEF; VCS for GLS.  All kit-derived views stay on the
hosts (tau1, tau5, usask: /tmp/ckp908/qc18acc/build/pnr/<tag>); the repo keeps scripts and summaries
(`results/pnr_v3/`).

Labels: **[M]** measured in simulation (GLS); **[S]** static timing / area of the routed design (PrimeTime with the
def2spef SPEF, or OpenROAD's own estimate where marked "OR est."); **[P]** PrimeTime PX power of the routed netlist
with the gate-level SAIF; **[Mo]** model (macro access energy from the ARM datatables, "+dat"; 0.8 V macro scaling).
Pre-route numbers are synthesis estimates (WLM, ideal clock).

Runs:

| tag | host | design | recipe | floorplan | status |
|---|---|---|---|---|---|
| `qa_t1` | usask | v2 | v2 recipe ([pnr.md](pnr.md)) | 3156.6 x 2806.2 um, band 400 um | routed (reference) |
| `qa3_t1` | tau1 | v3 | v2 recipe (`qa3.cfg`) | 3363.8 x 2836.8 um, band 700 um | routed (detailed route stopped after iteration 4) |
| `qa3_t5b` | tau5 | v3 | improved (`qa3b.cfg`) | 3363.8 x 3087.0 um, band 950 um | routed (detailed route stopped after iteration 4) |
| `qa_t1b` | usask | v2 | improved (`qab.cfg`) | 3156.6 x 3106.8 um, band 700 um | routed, 17 iterations |
| **`qa3_t5c`** | tau5 | v3 | improved + hub padding 1 site (`qa3c.cfg`) | as `qa3_t5b` | **routed, detailed route stopped after iteration 8 (gdb); route of record** |
| `qa3_u5d` | usask | v3 | improved + hub padding 2 sites | as `qa3_t5b` | global route failed (GRT-0119, overflow in the hub) |
| `qa3_u5g` | usask | v3 | improved, GR_ADJUST 0.40 | as `qa3_t5b` | stopped in global route after 2.5 h (overflow not resolved) |
| `qa3_p1` / `qa3_p2` / `qa3_d5` / `qa3_o5` / `qa3_o3` | tau5 | v3 | placement experiments (section 11.3) | as `qa3_t5b` | place step only |

**Detailed route was not completed for either v3 run.**  v3 detailed-route iterations 3 / 4 take 70-80 min each (v2:
17-34 min), so 16-24 iterations did not fit the time box.  The v3 baseline `qa3_t1` was stopped after iteration 4
(end iteration lowered 24 -> 4 in the running process with gdb, `drt::END_ITERATION`, as in v2): 83 318 DRC markers.
tau5 and usask rebooted at ~15:16 CST while `qa3_t5b` / `qa_t1b` were in detailed route; both were restarted from
their `db/cts.odb` (the post-CTS / GRT results reproduced: grt_opt -2.223 / -0.196 ns vs -2.225 / -0.192 ns) with
end iteration 16; `qa3_t5b` was then also stopped after iteration 4 (gdb): **70 584 DRC markers** (mostly shorts /
spacing of an unfinished search-and-repair; `qa_t1b` reached 251 after 17 iterations).  The v3 post-route timing,
power and GLS below are therefore of the iteration-4 routing (complete connectivity, all nets routed, DRC not
clean); the wire RC of an unfinished route differs little from the final one (the remaining work is local
rip-up / re-route of markers), but this is an open item.

**This revision (section 11):** before restarting, the iteration-4 markers and a fresh global-route congestion report
of `qa3_t5b` were analysed: 61 % of the markers sit in one 200-um column at the centre of the band (the act-buffer /
xbar / head hub), placed at 93-100 % cell utilisation, while global route reports no overflow.  Placement padding of
the hub cells was the change chosen (lower density and a tighter global-placement overflow did not move the hub);
the route was re-run from placement (`qa3_t5c`, pad 1, tau5) and stopped after iteration 8 at **70 675 markers** -
equal to `qa3_t5b` at iteration 4, all in the hub; pad 2 overflows in global route.  The detailed route of v3 does
not converge with these flow-level changes; post-route timing / power / antenna / GLS were redone on `qa3_t5c`.

## 0. Summary: v2 vs v3 after place & route

| quantity | v2 `qa_t1` (v2 recipe) | v2 `qa_t1b` (improved) | v3 `qa3_t1` (v2 recipe) | v3 `qa3_t5b` (improved; iteration 4, superseded as the route of record) | **v3 `qa3_t5c` (improved + hub padding, 9 iterations)** | label |
|---|---|---|---|---|---|---|
| die | 8.858 mm2 | 9.807 mm2 | 9.542 mm2 | 10.384 mm2 | **10.384 mm2** | [S] |
| pre-route total area (DC) | 6.430 mm2 | 6.430 mm2 | 6.514 mm2 | 6.514 mm2 | 6.514 mm2 | [S] |
| standard cells after P&R (DC) | 1.252 mm2 (0.882) | 1.225 mm2 (0.882) | 1.807 mm2 (1.176) | 1.788 mm2 (1.176) | 1.788 mm2 (1.176) | [S] |
| core utilisation (macros + cells) | 0.779 | 0.700 | 0.759 | 0.695 | 0.695 | [S] |
| detailed route / DRC markers | 23 it. / 255 | 17 it. / 251 | stopped after it. 4 / 83 318 | stopped after it. 4 / 70 584 | stopped after it. 8 (gdb) / **70 675** | [S] |
| antenna violations (nets) | 192 | 147 | not run | 129 | **137** | [S] |
| hold after route, tt / ss (PT) | -0.132 / -0.309 ns | -0.043 / -0.152 ns | -0.381 / -0.692 ns | -0.394 / -0.686 ns | **-0.459 / -0.775 ns** (153 / 181 endpoints) | [S] |
| **fmax reg2reg ss / tt** | 172.5 / 288.3 MHz | 167.5 / 257.1 MHz | 101.1 / 179.2 MHz | 185.0 / 295.2 MHz | **148.9 / 272.4 MHz** | [S] |
| fmax logic-only (no macro paths) ss / tt | 172.5 / 288.3 | 178.0 / 313.0 | 101.1 / 179.2 | 192.5 / 314.1 | 148.9 / 272.4 | [S] |
| fmax incl. host IO ss / tt | 142.8 / 242.7 (ideal-edge IO) | 167.5 / 257.1 (IO ref) | 101.1 / 179.2 (ideal-edge) | 185.0 / 295.2 (IO ref) | 148.9 / 272.4 (IO ref) | [S] |
| pre-route fmax ss / tt | 303.2 / 463.3 | 303.2 / 463.3 | 303.2 / 463.4 | 303.2 / 463.4 | 303.2 / 463.4 | [S] synthesis |
| power clock (tt fmax rounded down) | 285.7 MHz | 256.4 MHz | 178.6 MHz | 294.1 MHz | **270.3 MHz** (3.7 ns) | |
| **power (+dat) / energy per inference** | 272.2 mW / 152.4 uJ | 229.0 mW / 142.9 uJ (3.5 ns: 252.2 / 141.2) | 260.9 mW / 119.0 uJ | 388.6 mW / 107.6 uJ | **361.0 mW / 108.8 uJ** | [P] + [Mo] |
| post-route / pre-route energy | x1.65 | x1.55 (x1.53 at 3.5 ns) | x1.74 | x1.57 | x1.59 | |
| clock-tree cells / whole clock network share | 17.7 % / 31.2 % | 14.8 % / 29.3 % | 15.5 % / 24.5 % | 13.7 % / 23.5 % | 13.6 % / 23.3 % | [P] |
| SAIF annotation | 89.1 % | 90.2 % | 87.1 % | 87.3 % | **87.3 %** | [P] |
| inferences / s at the power clock | 1 786 | 1 603 | 2 193 | 3 611 | **3 319** | [M] cycles |
| zero-delay GLS of the routed netlist, image 0 | PASS | PASS | PASS | PASS (81 438 cycles = RTL) | **PASS** (81 438 cycles = RTL) | [M] |

**Route of record = `qa3_t5c`** (this revision, section 11): the improved recipe plus 1 site of placement padding on
the act-buffer / xbar / head hub, detailed route run for 9 iterations (0-8; end iteration lowered 24 -> 8 with gdb
when it had stalled at ~4-7 % per 70-80-min iteration): 70 675 markers, the same as `qa3_t5b` after 5 iterations,
all of them now inside the hub strip (x 1400-2000 um); neither run converges, and the padding costs timing (PPU lane
2 and act-macro -> xbar paths, tt 272.4 vs 295.2 MHz).  The `qa3_t5b` iteration-4 numbers are kept above and in
sections 5-8 (superseded as the route of record; they remain the faster, equally unclean point).

v3 improved (`qa3_t5b`) vs v2 routed: x0.706 energy per inference (pre-route x0.741), x2.02 throughput, x1.17 die area,
fmax +2.4 % tt / +7.2 % ss.  The improvement study's main lever is the floorplan (logic band large enough for the
logic at the placement density); the flow settings (IO model, CKBD4 sinks, post-GRT macro hold margin) each give a
few percent of power or hold, and one side effect (late weight-macro clock) caps the v2b / v3 reg2reg fmax at the
weight macro -> head FC path, 6-18 % below the logic-only fmax.

## 1. v3 floorplan and flow

| item | v3 baseline `qa3_t1` | v3 improved `qa3_t5b` |
|---|---|---|
| die | 3363.8 x 2836.8 um = **9.542 mm2** (core 9.413) | 3363.8 x 3087.0 um = **10.384 mm2** (core 10.250) |
| macros | 57 fixed, 5.338 mm2: tiers top / bottom: weight halves (top `u_wmem_e` 0-2 + par 0 + descriptor RF, bottom `u_wmem_o` 0-2 + par 1) outermost, then 3 rows of 8 act halves per side (`macro_place3.tcl`: row = one buffer's 8 banks, lo halves on top, hi halves mirrored below), signal-pin edges facing the band | same |
| logic band | 700 um | **950 um** |
| spacing, IO, PDN | as v2 (halo 10 um, 60-um row channels, 20-um edge rows, 95 IO pins on the left band edge; M1 rails, M4 / M7 / M8 straps); the 48 act halves are rf_sp_adv macros (rings M2 / M3, OBS M1-M3) and get the RF macro grid (M4 straps, M3 -> M4 -> M7, `pdn_macro.tcl`); check_power_grid VDD / VSS: connected | same |
| placement (gpl density 0.6, 512 x 512 bins, DRV repair of violating nets) | cells 1.701 mm2, 16.6 % of the cell area outside the band | cells 1.695 mm2, 10.5 % outside the band (act-buffer pin logic in the channels) |
| CTS | TritonCTS `-balance_levels`, sink buffer CKBD16 | `-balance_levels -sink_clustering_buffer CKBD4` |
| post-CTS / post-GRT repair | setup (WNS mode) + hold, synthesis IO model | same + host IO relative to the host-register clock, +0.2 ns macro hold margin at GRT |
| detailed route | end iteration 24, stopped after iteration 4 (gdb) | end iteration 16 |

## 2. Why the v2 routed result lost against pre-route (diagnosis, v2 run qa_t1)

Measured on the v2 checkpoints / reports; [S] = OpenROAD or PrimeTime static timing, [P] = PT power.

1. **Logic spilled out of the logic band into the macro-row channels.**  The 400-um band holds 1.19 mm2 of rows, the
   v2 logic is 1.16 mm2 after placement repair, and global placement at target density 0.6 needs ~1.9 mm2: 34.7 %
   of the standard-cell area (0.403 mm2, of it 0.229 mm2 PE-array logic and 0.058 mm2 PPU lanes) is placed outside
   the band, in the 60-um channels between the activation-macro rows (40 um usable) [measured on `db/place.odb`,
   `pnr/inband.tcl`].  Cell bounding boxes (`pnr/bbox.tcl`): PE (4,4), the PE of the post-route critical path, sits at y 738-1013 um
   (band 1204-1604 um), strung over 684 x 275 um instead of ~120 x 120 um; PPU lane 6 at y 846-1327; u_seq up to y
   2066.  Inside such a block the DC (wire-load) D0 / D1 cells drive 0.02-0.08 pF of wire.
2. **The critical PE path is cell-delay bound by those wires** [S]: u_xbar/s3_code_reg_49_ -> PE (4,4) rot2 -> tadd
   -> acc -> sh_out_reg_59_ is 1.84 ns at tt pre-route (DC netlist, WLM, PT) and 3.22 ns post-route (SPEF): rot2
   0.29 -> 0.73 ns, tadd 0.32 -> 1.01 ns (CKND2D0 0.22 ns, IOA21D0 0.33 ns), the xbar-to-PE broadcast 0.17 -> 0.37
   ns, the ripple accumulator +0.15 ns.  Clock skew on this path is +0.02 ns (not the cause).
3. **repair_timing only repaired the worst endpoint.**  In this OpenROAD build `repair_timing -setup` defaults to
   `-repair_tns 0` (Resizer.tcl: `repair_tns_end_percent 0.0`): it works the single worst endpoint until its slack
   stops improving and returns (RSZ-0062).  v2 post-CTS: 15 840 violating endpoints, 251 resizes, 3 buffers; post-GRT
   2 545 resizes.  With `-repair_tns 100` it went through endpoints, but at 3 550 passes / 15 min with TNS -1.5 % and
   the WNS endpoint (weight macro -> head FC) unchanged.
4. **Hold buffers from the IO model.**  The synthesis SDC times the host-port IO against the ideal clock edge; after
   CTS every register is 1.0-1.5 ns (tt) later, so all host-input paths need that much hold delay: 9 571 hold buffers
   after CTS + 1 603 after GRT (top-level glue 23 mW [P]).  The same buffers then make the host-input setup the worst
   "incl. IO" path (host_addr -> u_host/h1_addr_reg: 242.7 MHz tt).
5. **Clock tree = CKBD16 everywhere.**  TritonCTS characterises with the largest buffer of the list: 6 480 clock-tree
   cells after CTS, all CKBD16, 0.261 mm2 (21 % of the cell area), 1 230 gated subtrees each with its own CKBD16
   levels (`-balance_levels`); post-route 7 319 cells = 48.2 mW, 17.7 % of the total [P].
6. **Post-route hold at the macros.**  129 of the 139 tt hold violations (PT) end at macro D / A pins (host write data
   -> weight macro D, AGU -> act macro A), -0.13 ns tt / -0.31 ns ss, all met at the GRT estimate: macro hold time
   0.21 ns, the macro clock is a 1-sink net behind its CKLNQD2 (CTS skips it), and the routed clock / data wires
   differ from the global-route estimate.

## 3. Improvement attempts (bounded study, ~2.5 h of the 12 h)

Goal: recover part of the v2 post-route loss (energy x1.65 with 31 % in the clock network, tt fmax 463 -> 288 MHz,
hold failing on the host write path).  Attempts were evaluated on the v2 checkpoints with OpenROAD's estimate after
the post-CTS repair (`cts_opt`, placement parasitics) and after the post-GRT repair (`grt_opt`, global-route
parasitics), 3.3 ns, worst path incl. IO [S, OR est.] (for v2 the GRT estimate matched PrimeTime post-route within
0.01 ns at ss and 0.08 ns at tt); clock-tree power = OpenROAD `report_power` Clock group with its default activity
(the clock toggles every edge; data activity 0.1), a relative measure only.  Tools: `grt_only.tcl`
(cts.odb -> post_cts.tcl -> global route -> post_grt.tcl), `diag_cts.tcl`, `inband.tcl`, `bbox.tcl`.  The
successful combination was then routed for v2 (`qa_t1b`, full post-route numbers) and v3 (`qa3_t5b`).

| run | change vs the v2 recipe | where from | cts_opt ss / tt | grt_opt ss / tt | hold buffers cts + grt | clock tree after CTS | outcome, mechanism |
|---|---|---|---|---|---|---|---|
| base | none (routed run qa_t1) | | -2.802 / -0.273 | -2.487 / -0.085 | 9 571 + 1 603 | 6 480 CKBD16, 0.261 mm2; Clock group 30.6 mW | reference |
| X1 | IO delays relative to the host-register clock (`QA_IO_REF`) | qa_t1 cts.odb | -2.198 / +0.007 | -2.408 / -0.053 | 6 383 + 1 606 | as base | kept: -3 190 hold buffers (the ideal-edge IO model's input hold fixes), setup ss +0.08 / tt +0.03 ns at GRT |
| X3 | X1-like + `repair_timing -repair_tns 100` | qa_t1 cts.odb | (stopped) | | | | dropped: 3 550 passes in 15 min, WNS endpoint (weight macro -> head FC, -1.58 ns) never improved, TNS -1.5 % |
| X5 | timing-driven placement (v2 run qa_t5, stopped at overflow 0.13) + X1 | qa_t5 cts.odb | -2.187 / -0.087 | -2.235 / -0.277 | 5 406 + 1 572 | 6 450 CKBD16 | dropped: ss +0.17 ns, tt -0.22 ns vs X1 (mixed; TD gpl itself unstable on this die) |
| X2b | X5 + CTS sink buffer CKBD4 | qa_t5 place.odb | -2.025 / -0.072 | -2.245 / -0.174 | 5 473 + 1 463 | 5 276 CKBD16 + 1 064 CKBD4 + 110 CKBD8, 0.229 mm2; Clock 19.5 mW (-36 %) | kept: clock power -36 % (default activity), setup equal / +0.10 ns tt vs X5 |
| X2c | X2b without `-balance_levels` | qa_t5 place.odb | -2.102 / -0.158 | -2.388 / -0.397 | 6 618 + 1 594 | 5 602 cells, 0.220 mm2; Clock 15.9 mW | dropped: unbalanced gated subtrees -> +1 145 hold buffers, tt -0.22 ns at GRT |
| X2d | X2b + clustering 30 sinks / 100 um | qa_t5 place.odb | (CTS only) | | | 6 178 cells, Clock 18.0 mW | not pursued (smaller gain than X2b's buffer change) |
| X2e | X2b + `-buf_list {CKBD4 CKBD8}` | qa_t5 place.odb | (CTS only) | | | identical to X2b | no effect: TritonCTS keeps CKBD16 for the tree levels (root / characterisation) |
| X6 | X1 + focused setup repair (macro / IO paths false-pathed for one pass) + macro hold 0.15 | qa_t1 cts.odb | -2.412 / +0.015 | -2.621 / -0.169 | 8 026 + 1 520 | as base | dropped: the focused pass also stops at its worst endpoint (414 / 4 165 resizes); the macro margin costs +1 640 hold buffers |
| X7 | X6 with `-repair_tns 30 -max_passes 4000` | qa_t1 cts.odb | (stopped) | | | | dropped: first repair call not finished after 35 min |
| X8 | X1 + DRV repair of the violating nets after CTS and after the hold legalisation | qa_t1 cts.odb | -7.216 / -2.127 | (stopped) | 5 621 | as base | dropped: 3 662 + 2 961 DRV nets repaired, the inserted buffers overfill the PE region and legalisation scatters whole PEs (0.07-0.10 pF on every D0 / D1 net of PE (4,2)) |
| v2i | X1 + X2b CTS + macro hold 0.2 (GRT only), non-TD placement | qa_t1 place.odb | -2.260 / -0.006 | -2.919 / -0.159 | 6 343 + 3 849 | | stopped before detailed route (replaced by v2b) |
| **v2b** (`qa_t1b`) | **v2i + 700-um band (die 3156.6 x 3106.8 um)**, routed | new placement | -2.423 / -0.424 | -2.499 / -0.496 | 3 396 + 3 784 | 7 036 cells post-route | placement ss -1.715 (base -2.487), 10.2 % of the cell area outside the band (base 34.7 %); post-route section 5 / 6 |

What each attempt did, mechanistically:

* **IO reference (X1, kept).**  Re-referencing the host-port input / output delays to the propagated clock of
  `u_host/h1_addr_reg_0_` (`set_input_delay -reference_pin`) removes the ~1.0-1.5 ns of apparent hold requirement
  that the ideal-edge IO model puts on every host input after CTS: 9 571 -> 6 383 post-CTS hold buffers (-3 190), and
  the post-CTS tt setup goes from -0.27 to +0.01 ns because the hold buffers no longer sit on host-input setup paths.
  At GRT the gain is small (+0.08 ss / +0.03 tt): the remaining worst paths are internal.  Sign-off has to use the
  same model: the v2 routed netlist (built for the ideal-edge model) re-timed with the reference model has a host
  setup path at -1.97 ns tt (its ~1.3 ns of input hold buffers are now pure setup delay).
* **repair_tns (X3, X7, dropped).**  With `-repair_tns` the resizer visits every violating endpoint but spends
  thousands of passes without changing WNS; 15 840 endpoints at ss make one call take > 35 min, and the fmax-setting
  worst path (weight SRAM -> 1 mm of wire -> head FC, or the PE in the channel) is not fixable by sizing.
* **Focused repair (X6, dropped).**  Hiding the macro / IO paths for one pass only moves the "worst endpoint" the
  WNS-mode resizer gives up on; 414 resizes, no WNS change.
* **Timing-driven placement (X5, dropped).**  ss +0.17 ns, tt -0.22 ns at GRT, and the TD global placement itself
  diverges on this die unless stopped early (pnr.md).
* **CTS buffers (X2b kept, X2c / X2d / X2e not).**  `-sink_clustering_buffer CKBD4` turns 1 064 leaf buffers into
  CKBD4 and the Clock group drops 30.4 -> 19.5 mW with equal or better setup; without `-balance_levels` (X2c) the
  gated subtrees are unbalanced (+1 145 hold buffers, tt -0.22 ns); `-buf_list {CKBD4 CKBD8}` does not change the
  tree (TritonCTS keeps CKBD16 for the H-tree levels: 5 276 of 6 450 cells).  Side effect found after routing
  (v2b): the balance-level buffer in front of the four bottom weight-macro clock gates is now a CKBD4 driving 0.24 pF,
  the macro clock arrives 0.48 ns after the head registers, and the weight macro -> head FC path becomes the worst
  post-route path (below).
* **DRV repair after CTS (X8, dropped, harmful).**  3 662 + 2 961 nets repaired; the inserted buffers overfill the
  PE regions and the 300-um legalisation scatters whole PEs (every D0 / D1 net of PE (4,2) at 0.07-0.10 pF): ss -7.2,
  tt -2.1 ns after CTS.
* **Macro hold margin (kept at GRT only).**  0.15-0.3 ns of hold uncertainty on the macro CLK pins fixes the
  post-route macro hold violations but, applied after CTS, adds 1 600-2 000 hold buffers and displacement (v3 first
  attempt A: 12 126 hold buffers, cts_opt -10.5 / -3.9 ns); applied in the post-GRT repair only (0.2 ns) it costs
  ~2 200 extra post-GRT hold buffers on v2 (3 784 vs 1 603) and leaves tt hold at -0.04 ns (11 endpoints; v2:
  -0.13 ns, 139); on v3 (route unfinished) 0.2 ns was not enough (tt -0.39 ns, section 8).
* **Logic-band size (the main finding, kept).**  Section 2 item 1: with the 400-um band 34.7 % of the v2 cell area
  (0.229 mm2 of it PE logic) is placed in the macro-row channels.  A 700-um band (v2b, die 9.807 mm2, +10.7 %)
  leaves 10.2 % outside (only act-buffer pin logic); placement ss WNS -2.49 -> -1.72 ns; post-route the logic-only
  reg2reg fmax rises 288.3 -> 313.0 MHz tt.  For v3 the 950-um band (16.6 -> 10.5 % outside) is what turns the v3
  result around (section 4).

## 4. v3 runs stage by stage (OpenROAD estimate, worst path incl. IO, 3.3 ns) [S, OR est.]

| stage | v3 baseline `qa3_t1` (band 700, v2 recipe) | v3 A' (band 700, improved settings; stopped) | **v3 improved `qa3_t5b` (band 950)** |
|---|---|---|---|
| placement (ss / tt WNS ns) | -2.764 / -0.133 | -3.139 / -0.191 | **-1.668 / +0.306** |
| after CTS | -5.495 / -1.390 | -4.570 / -0.867 | -1.987 / -0.246 |
| after post-CTS repair (cts_opt) | -6.513 / -2.131 | -6.122 / -1.871 | -1.707 / -0.224 |
| global route (before repair) | -7.934 / -2.817 | -6.963 / -2.275 | -2.277 / -0.446 |
| after post-GRT repair (grt_opt) | -7.835 / -2.540 | | -2.223 / -0.196 |
| worst path at grt_opt | u_seq/dw_reg -> PPU lane 10 res5 (D0 cells, 0.6-1.1 ns slews) | (PPU lane 10) | ss: u_seq/dw_reg -> PPU lane 2; tt: host write data -> act macro |
| hold buffers after CTS + after GRT | 10 087 + 2 870 | 7 468 | 5 384 + 4 046 |
| cell area at grt_opt | 1.807 mm2 | | 1.788 mm2 |

A' isolates the flow settings on the 700-um floorplan: the host-IO reference removed 2 600 hold buffers, CKBD4 sinks
cut the CTS step's ss loss (-2.76 -> -5.50 vs -3.14 -> -4.57 ns), but the PPU lanes placed in the macro-row
channels (lane 10 at y 885-1336 um, band 1069-1769) still dominate: their D0 / D1 cells drive 0.03-0.05 pF and the
u_seq/dw_reg -> lane 10 path is 5.5-7.0 ns at tt.  The 950-um band (B) keeps every PE / PPU lane / control block inside the band (block bounding
boxes, `bbox.tcl`; 10.5 % of the cell area outside = act-buffer pin logic) and gains 5.6 ns (ss) / 2.3 ns (tt) over the
baseline at the GRT estimate.  First attempt A (band 700, 0.3 ns macro hold margin already after CTS): 4 039 hold endpoints,
12 126 hold buffers, cts_opt -10.47 / -3.92 ns - the margin was then restricted to the post-GRT repair.

## 5. Post-route timing (PrimeTime, def2spef SPEF, propagated clock, synthesis SDC) [S]

`run.sh pt <tag>` (`pt_post_qa.tcl`); improved runs with `QA_IO_REF=1` (the IO model they were repaired with).
fmax = 1 / (3.3 ns - WNS).  "reg2reg" = worst path between clocked cells (incl. macros, IO excluded), "logic" = the
same without paths from / to a macro pin, "incl. host" = all paths incl. the host-port IO.

| run | corner | reg2reg WNS | **reg2reg fmax** | logic fmax | incl. host | worst reg2reg path | hold WNS (endpoints) |
|---|---|---|---|---|---|---|---|
| v2 `qa_t1` | ss | -2.497 | **172.5** | 172.5 | 142.8 | u_xbar/s3_code -> PE (4,4) sh_out | -0.309 (126) |
| v2 `qa_t1` | tt | -0.169 | **288.3** | 288.3 | 242.7 | same | -0.132 (139) |
| v2 `qa_t1b` (improved) | ss | -2.669 | **167.5** | 178.0 | 167.5 | weight macro (bank 4) -> u_head/dot2 | -0.152 (51) |
| v2 `qa_t1b` (improved) | tt | -0.589 | **257.1** | 313.0 | 257.1 | same (macro clock +0.48 ns late) | -0.043 (11) |
| v3 `qa3_t1` (v2 recipe) | ss | -6.593 | **101.1** | 101.1 | 101.1 | u_seq/dw_reg -> PPU lane 10 res5 | -0.692 (91) |
| v3 `qa3_t1` (v2 recipe) | tt | -2.279 | **179.2** | 179.2 | 179.2 | same | -0.381 (69) |
| **v3 `qa3_t5b` (improved)** | ss | -2.105 | **185.0** | 192.5 | 185.0 | weight macro (wmem_e bank 0) -> u_head/dot2 | -0.686 (153) |
| **v3 `qa3_t5b` (improved)** | tt | -0.088 | **295.2** | 314.1 | 295.2 | same | -0.394 (120) |

Pre-route (DC netlist, WLM, ideal clock): v2 / v3 ss 303.2 / 303.2, tt 463.3 / 463.4 MHz.  SPEF annotation (PT):
v3 baseline 415 373 of 426 318 nets with RC networks (97.4 %; not annotated: pin-to-pin and driverless nets, as
v2); v3 improved 412 785 of 423 732 (97.4 %); v2 improved 288 370 of 298 154 (96.7 %).

## 6. Post-route power (PTPX tt 1.0 V, SDF SAIF of image 0 flattened onto the routed netlist, +dat macro model) [P] + [Mo]

`power.sh -t <tag> <period>` + `report.py <period> <tag>`; clock = the post-route tt reg2reg fmax rounded down to
0.1 ns of period, the SAIF rescaled to it (same toggles per cycle).  SAIF annotation = nets of the routed netlist
annotated from the SAIF; the rest (P&R-inserted buffers, clock tree) get propagated activity.

| quantity | v2 `qa_t1` | v2 `qa_t1b` | v2 `qa_t1b` | v3 `qa3_t1` | **v3 `qa3_t5b`** |
|---|---|---|---|---|---|
| clock (= post-route tt fmax, rounded down) | 3.5 ns (285.7 MHz) | 3.9 ns (256.4 MHz) | 3.5 ns (same clock as v2; not met, comparison only) | 5.6 ns (178.6 MHz) | **3.4 ns (294.1 MHz)** |
| PT total mW (int / switch / leak) | 253.38 (140.07 / 86.48 / 26.83) | 212.12 (115.59 / 70.04 / 26.48) | 233.33 (128.80 / 78.05 / 26.48) | 234.25 (121.90 / 82.82 / 29.53) | 344.72 (187.43 / 127.97 / 29.32) |
| **+dat total mW** | 272.20 | 229.02 | 252.16 | 260.90 | **388.60** |
| **uJ / inference (+dat)** | 152.42 | 142.89 | 141.19 | 118.99 | **107.60** |
| vs pre-route (92.4 / 68.5 uJ at 400 MHz) | x1.65 | x1.55 | x1.53 | x1.74 | **x1.57** |
| leakage share | 9.9 % | 11.6 % | 10.5 % | 11.3 % | 7.5 % |
| CTS clock-tree cells mW (% of +dat) | 48.23 (17.7 %) | 33.98 (14.8 %) | 37.76 (15.0 %) | 40.54 (15.5 %) | 53.10 (13.7 %) |
| PT clock_network group (tree + ICGs + register clock pins + nets) | 84.80 mW (31.2 %) | 67.10 (29.3 %) | 74.60 (29.6 %) | 64.00 (24.5 %) | 91.50 (23.5 %) |
| top-level glue (repair / hold buffers) mW | 23.14 | 19.35 | 21.33 | 25.39 | 36.82 |
| PE array (u_array) mW | 113.83 | 97.31 | 107.96 | 103.88 | 162.85 |
| PPU (u_ppu) mW | 30.85 | 26.41 | 29.32 | 28.91 | 45.33 |
| act / weight macros +dat mW | 24.77 / 15.52 | 23.08 / 14.61 | 24.80 / 15.49 | 28.00 / 17.56 | 42.15 / 24.51 |
| SAIF annotation (nets from the SAIF) | 89.06 % | 90.20 % | 90.20 % | 87.10 % | 87.31 % |
| inferences / s at this clock | 1 786 | 1 603 | 1 786 | 2 193 | **3 611** |

Full tables: `results/pnr/post_3.5ns*` (v2), `results/pnr/qa_t1b_report_{3.9,3.5}ns.md`,
`results/pnr_v3/qa3_t1_report_5.6ns.md`, `results/pnr_v3/qa3_t5b_report_3.4ns.md`.

* **v2, flow + floorplan improvements at the same clock (3.5 ns): 252.2 vs 272.2 mW, 141.2 vs 152.4 uJ (-7.4 %).**
  Clock-tree cells -10.5 mW (CKBD4 sinks), top-level glue -1.8 mW (fewer IO hold buffers; the macro hold margin
  added some back), PE array -5.9 mW / PPU -1.5 mW (shorter wires inside the band), macros unchanged.  The post-route / pre-route energy ratio goes from x1.65 to x1.53.
* **v3 improved: 107.6 uJ / inference at 294 MHz, x0.706 the v2 routed result (152.4 uJ at 286 MHz)** (pre-route
  ratio x0.741), 3 611 inferences / s (x2.0 of v2 routed).  v3 baseline (v2 recipe): 119.0 uJ, but at 179 MHz.
* SAIF coverage 87.3 % (v3): the rest are P&R-inserted nets (clock tree, repair / hold buffers, 12.0 %, activity
  propagated) and 0.67 % "default" nets: 2 822, ~1 360 more than the tau1 runs: net names of the `u_array` top-level shift chain that
  the tau5 re-synthesis of `qa3_w3.3` named differently from the tau1 netlist the SAIF was simulated on (same
  logic: 237 of 457 779 netlist lines differ, all net numbering); with `power_default_toggle_rate 0` those count as
  static, a small under-estimate of the shadow-chain switching.

## 7. Gate-level simulation of the routed netlists (zero delay, VCS, image 0) [M]

`QA_V=3 qc18acc/gls/run_gls.sh start <host> <tag>_pnr 0 1` with `build/syn/<tag>_pnr/qa_top.v` = the routed
`out/qa_top.v` (flat; clock tree, repair / hold buffers, decaps; `gen_snap.py` handles the flat names).

| netlist | result | cycles (START..DONE) |
|---|---|---|
| v3 `qa3_t1` routed | **RESULT PASS**: all 10 logits + 20 stored maps bit-exact, 22 cycle counters = RTL (0 differ) | 81 438 |
| **v3 `qa3_t5b` routed** | **RESULT PASS**: all logits + 20 maps bit-exact, 22 counters = RTL (0 differ) | 81 438 |
| v2 `qa_t1b` routed | **RESULT PASS**, 22 counters = RTL | 159 982 |
| **v3 `qa3_t5c` routed** (iteration 8) | **RESULT PASS**: all logits + 20 maps bit-exact, 22 counters = RTL (0 differ); simv then hit a bus error in its exit handler (rc 135, after the result and the SAIF were written) | 81 438 |

## 8. DRC, antennas, hold

| run | detailed route | DRC markers | antenna (check_antennas, separate session) | hold after route (PT) |
|---|---|---|---|---|
| v2 `qa_t1` | 23 iterations | 255 | 192 nets / 192 pins | tt -0.132 (139), ss -0.309 (126) |
| v2 `qa_t1b` | 17 iterations | 251 (129 short, 64 metal spacing, 32 cut short, 26 cut spacing) | 147 nets / 147 pins | tt -0.043 (11), ss -0.152 (51) |
| v3 `qa3_t1` | stopped after iteration 4 | 83 318 | not run (not meaningful at this DRC count) | tt -0.381 (69), ss -0.692 (91) |
| v3 `qa3_t5b` (superseded) | stopped after iteration 4 | 70 584 (56 387 short, 9 878 metal spacing, 4 222 cut spacing, 97 other) | 129 nets / 129 pins | tt -0.394 (120), ss -0.686 (153): host write data -> weight macro D |
| **v3 `qa3_t5c`** | stopped after iteration 8 | **70 675** (60 038 short, 8 233 metal spacing, 2 347 cut spacing, 57 other; 99.4 % in x 1400-2000 um) | **137 nets / 137 pins** | **tt -0.459 (153), ss -0.775 (181)**: host write data -> weight macro D; no post-route repair (11.6) |

Not covered by the router's DRC (flow README): M1 MINIMUMCUT rules dropped for pin access, LEF57 rules, metal fill;
no antenna repair (repair_antennas segfaults in this build).

## 9. 0.8 V point

Pre-route only, [lowv.md](lowv.md) section "v3": tt 0.8 V logic-only fmax 306.8 MHz [S]; at 300 MHz 156.5 mW,
42.5 uJ / inference [P] with the macros [Mo] (V^2 energy, leakage x 0.44).  Not repeated on the routed netlist
(the routed v3 design does not reach 300 MHz even at 1.0 V tt with its macro paths: 295 MHz).

## 10. Open issues

* **v3 detailed route does not converge** (`qa3_t5c`: 70 675 markers after 9 iterations, -4 % per 70-min
  iteration at the end; `qa3_t5b` 70 584 after 5, `qa3_t1` 83 318 after 5): the act-buffer / xbar / PE hub at the
  centre of the band (section 11).  Needs a floorplan / architecture change (distributed xbar, wider band or M8
  over the hub), not a flow setting.  Timing / power / GLS of the v3 routed netlists are of unclean routings.
* **Weight-macro clock latency** (v2b, v3 improved): with CKBD4 sink buffers the four macro clock gates of a weight
  tier hang on one CKBD4 balance-level buffer (0.24 pF): macro CLK +0.48 ns vs the head registers, and the weight
  macro -> head FC path limits fmax (v2b tt 257 vs logic-only 313 MHz).  Next step: CKBD8 / CKBD16 for the macro
  clock-gate cluster (or a useful-skew / `set_clock_latency` budget on the macro CLK) while keeping CKBD4 for the
  register leaves.
* **Hold at the macro inputs** after route: v3 tt -0.46 ns (`qa3_t5c`, 153 endpoints; `qa3_t5b` -0.39 / 120), all
  host write data -> weight macro D, caused by the late weight-macro clock; the 0.2-ns post-GRT margin covers v2
  (-0.04 ns) but not v3; post-route ECO not attempted because the route is not stable (11.6, `hold_eco.tcl`).
* No antenna repair (segfault in this OpenROAD build); M1 MINIMUMCUT / LEF57 rules not checked; geometric SPEF
  (captable RC, no coupling).
* The v3 improved run used a tau5 re-synthesis of `qa3_w3.3` (identical logic, 237 netlist lines with different
  net numbering) with the tau1 SAIF (section 6).
* Host repos of tau5 / usask: their NFS home was not mounted after the reboot, so `git pull` from GitHub failed;
  the clones were updated from a git bundle (origin pointed at /tmp/ckp908/repo.bundle; still so on all three hosts).

## 11. Detailed-route convergence of v3: diagnosis and the hub-padding recipe (`qa3c.cfg`)

### 11.1 Where the 70 584 iteration-4 markers of `qa3_t5b` are [S]

`rpt/drt.drc.rpt` of `qa3_t5b` (iteration 4), binned by position (`gr_diag.tcl` / marker scan):

| | count | share |
|---|---|---|
| all markers | 70 584 | |
| by type: short / metal spacing / cut spacing / other | 56 387 / 9 878 / 4 222 / 97 | |
| shorts by layer: M2 / M3 / M4 / M5 / M6 / M7 | 34 239 / 11 961 / 4 140 / 4 203 / 1 224 / 604 | |
| x 1600-1800 um (all y) | 43 183 | 61.2 % |
| x 1400-2000 um | 60 264 | 85.4 % |
| y 1000-2000 um (the 950-um logic band) | 70 514 | 99.9 % |
| window x 1400-1800, y 1000-2000 | 55 392 | 78.5 % |
| markers of that window naming a net of: PE row 2 / u_xbar / top-level (repair, hold buffer) nets / u_act / act read data `ar_rdata` / u_head | 17 266 / 16 947 / 16 101 / 13 128 / 6 702 / 1 314 | |

The markers sit in one ~400 x 1000 um window at the centre of the band, on the act-buffer port logic (`u_act`, the
48 hold registers and port muxes of the act macros' read data), the xbar (128-b kw window) and the head: the hub
between the 48 act-macro read ports (macro rows above and below the band) and the 64 PEs.  v2 improved (`qa_t1b`) at
the same iteration had 10 361 markers; the v3 iteration count went 608 751 -> 248 765 -> 234 187 -> 111 494 -> 70 584
(iterations 0-4; iterations 3 / 4: 84 / 63 min).

### 11.2 Global-route congestion report [S, OR est.]

`gr_diag.tcl` on `qa3_t5b/db/route_dr.odb` (same netlist / placement; detailed wires removed, `global_route -verbose`
with the flow's 0.25 layer adjustment, M2-M7):

| layer | derated resource | demand | usage | overflow |
|---|---|---|---|---|
| M2 | 6 795 730 | 1 535 311 | 22.6 % | 0 |
| M3 | 6 494 874 | 2 378 910 | 36.6 % | 0 |
| M4 | 8 761 649 | 1 746 970 | 19.9 % | 0 |
| M5 | 12 677 280 | 1 740 731 | 13.7 % | 0 |
| M6 | 12 679 352 | 490 769 | 3.9 % | 0 |
| M7 | 10 846 646 | 596 536 | 5.5 % | 0 |
| total | 58 255 531 | 8 489 227 | 14.6 % | **0** |

The first GRT pass did overflow ("extra iterations to remove overflow"), the final solution has none, and the flow's
congestion report file is empty (`rpt/gr_congestion.rpt`, 0 bytes).  So, by GRT's edge-capacity model, the design is
not congested; M6 / M7 are almost unused.  Per 50-um tile, the guides' wire length relative to the tile's track
capacity is 130-160 % on M2 and 100-127 % on M3 in the hub window vs 50-110 % / 40-90 % in the rest of the band (a
relative indicator: guides are gcell-wide).  GRT does not see the problem because it lives inside the 3-um gcells:
the hub's cells are packed at 93-100 % cell utilisation (fillers excluded) over ~200 x 500 um (`gr_diag.tcl` tiles,
x 1600-1800, y 1350-1900; the band elsewhere 60-90 %), and the M2 / M3 tracks above them are consumed by pin access
of densely packed, pin-rich cells (muxes, flops) - the shorts are M2 (61 %) / M3 (21 %), i.e. at the pin-access
layers.  Global congestion margin or layer settings do not change that (the hub demand is local; M6 / M7 have free
capacity everywhere); cell density in the hub does.

### 11.3 Where the hub density comes from (placement experiments, `place` step only, ~10 min each) [S]

Global placement (target density 0.6, 512 x 512 bins) stops at 10 % overflow; with the hub's net count (3 072 act
read-data bits in, 64 x 128-b broadcasts out) the wire-length gradient wins over the density penalty there, and the
remaining overflow concentrates in the hub (a 0.15 mm2 region at 100 % instead of 60 % is ~4 % overflow by itself).
Tile statistics over the hub window (55 tiles of 50 x 50 um), worst setup at placement (OR est.):

| run | change vs `qa3b.cfg` | hub mean util | tiles > 95 % | place ss / tt WNS ns |
|---|---|---|---|---|
| `qa3_t5b` (placement of the routed run) | none | 0.906 | 29 / 55 | -1.668 / +0.306 |
| `qa3_d5` | PLACE_DENSITY 0.6 -> 0.5 | 0.839 | 21 / 55 | -1.839 / +0.072 |
| `qa3_o5` | gpl -overflow 0.10 -> 0.05 | 0.915 | 29 / 55 | -1.815 / +0.133 |
| `qa3_o3` | gpl -overflow 0.03 | | | stopped: Nesterov stalled at overflow 0.038 |
| `qa3_p1` | hub cells padded 1 site left / right | 0.884 | 6 / 55 | -2.261 / +0.091 |
| `qa3_p2` | hub cells padded 2 sites | 0.850 | 1 / 55 | -3.998 / -0.657 |

* A lower global density only empties the surroundings (band 50-65 %); the hub stays at 95-100 %.  A tighter
  overflow target does not move it either (and at 0.03 global placement stalls).
* `set_placement_padding -instances` is ignored by global placement in this build (gpl reports the same
  PlaceInstsArea) but enforced by detailed placement: every hub cell gets a free site on each side (M1 / M2 pin
  access) and the legaliser spreads the hub.  The price is wire length on the act-macro -> xbar paths (p2: worst
  ss path act macro -> u_xbar/win_reg, -4.0 ns at placement).
* Chosen: pad 1 for the routed run (`qa3c.cfg`, run `qa3_t5c`, tau5), pad 2 as a parallel hedge (`qa3_u5d`, usask,
  own synthesis of `qa3_w3.3`).  Padding is not stored in the odb and filler placement ignores it while
  check_placement checks it: `hub_post_cts.tcl` sets it again for the route step, `hub_post_grt.tcl` clears it
  before the fillers (the first attempt failed there: DPL-0033, 52 841 overlaps).

### 11.4 Routed run `qa3_t5c` (improved recipe + hub pad 1, tau5) [S] [P] [M]

Placement as `qa3_p1`; post-CTS repair ss / tt -1.923 / -0.230 ns, post-GRT -3.645 / -0.449 ns (OR est.; `qa3_t5b`
-2.223 / -0.196); global route without overflow.  Detailed route (end iteration 24, lowered to 8 with gdb after
iteration 5, `drt::END_ITERATION` at its symbol address, as for v2):

| iteration | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| `qa3_t5c` markers | 648 053 | 273 247 | 259 410 | 141 244 | 99 837 | 84 828 | 77 062 | 73 622 | **70 675** |
| `qa3_t5c` wall min | 28 | 25 | 23 | 104 | 82 | 79 | 71 | 70 | 67 |
| `qa3_t5b` markers | 608 751 | 248 765 | 234 187 | 111 494 | 70 584 | | | | |

Final 70 675 markers: 60 038 shorts (M2 34 148, M3 12 965), 8 233 metal spacing, 2 347 cut spacing; **99.4 % in x
1400-2000 um** (`qa3_t5b`: 85 %, with ~10 000 markers spread over the rest of the band).  The padding cleared the
periphery of the hub but not its core, and iterations 0-4 ended higher than in `qa3_t5b`.

Post-route (same steps as `qa3_t5b`; files `results/pnr_v3/qa3_t5c_*`):

| quantity | `qa3_t5c` | `qa3_t5b` (it. 4) | label |
|---|---|---|---|
| PT reg2reg fmax ss / tt (SPEF) | 148.9 / 272.4 MHz | 185.0 / 295.2 MHz | [S] |
| worst path | u_ppu lane 2 y5_reg -> out6_reg (ss and tt; 3.33 ns of data, ~33 cells) | weight macro -> u_head/dot2 | [S] |
| logic-only / incl. host IO, tt | 272.4 / 272.4 | 314.1 / 295.2 | [S] |
| hold WNS tt / ss (endpoints) | -0.459 (153) / -0.775 (181), host write data -> weight macro D | -0.394 (120) / -0.686 (153) | [S] |
| SPEF annotation | 412 838 of 423 785 nets (97.4 %) | 97.4 % | [S] |
| antenna (check_antennas on route_dr) | 137 nets / 137 pins | 129 / 129 | [S] |
| PTPX clock (tt fmax rounded down) | 3.7 ns (270.3 MHz) | 3.4 ns (294.1 MHz) | |
| PT total (int / switch / leak) | 320.66 mW (172.35 / 118.99 / 29.32) | 344.72 | [P] |
| **+dat total / energy per inference** | **361.0 mW / 108.8 uJ** | 388.6 mW / 107.6 uJ | [P] + [Mo] |
| clock-tree cells / clock_network group | 48.9 mW (13.6 %) / 84.1 mW (23.3 %) | 53.1 (13.7 %) / 91.5 (23.5 %) | [P] |
| PE array / PPU / top-level glue mW | 150.6 / 41.8 / 34.4 | 162.9 / 45.3 / 36.8 | [P] |
| SAIF annotation | 87.30 % (12.04 % P&R nets propagated, 0.67 % default) | 87.31 % | [P] |
| inferences / s at the power clock | 3 319 | 3 611 | [M] cycles |
| zero-delay GLS of the routed netlist, image 0 | PASS (81 438 cycles = RTL) | PASS | [M] |

The energy per inference is the same within 1 % (lower power at a lower clock); the slower clock comes from PPU lane 2
(its ~33-cell y5 -> out6 path is 3.33 ns of data from a clock arriving at 1.20 ns; the lane is re-placed by the
padding run, `qa3_t5b` had it off the critical list) and from the act-macro -> xbar paths that the padding stretched
(`qa3_p2` placement: -4.0 ns ss on act macro -> u_xbar/win_reg).

### 11.5 Higher global-route margin (`qa3_u5g`, usask) and pad 2 (`qa3_u5d`) [S, OR est.]

* `qa3_u5d` (pad 2, usask, own synthesis of `qa3_w3.3`): post-CTS ss / tt -2.211 / -0.127 ns, then **global route
  failed** (GRT-0119, "routing congestion too high"): 51 gcells with overflow 1, all horizontal, all at x 1479-1512
  um / y 1605-1698 um, on `ar_rdata`, `u_xbar` window / select nets and PE row 2 sums.  Spreading the hub by 2 sites
  turns its local wiring into a global-route overflow: direct evidence that the hub's wiring demand, not only its
  cell density, is the limit.
* `qa3_u5g` (`qa3b.cfg` with GR_ADJUST 0.25 -> 0.40 on M2-M7, no padding; its post-CTS numbers reproduce
  `qa3_t5b` exactly, -1.707 / -0.224 ns): global route had not finished after **2.5 h** (FastRoute still in its
  maze-routing rounds removing overflow; at 0.25 it takes ~20 min) and was stopped - with 40 % of every layer
  reserved global route cannot resolve the overflow in reasonable time, consistent with the hub demand of pad 2 (not
  proven: the overflow locations were not reported).  No detailed-route data for this variant.
* M8 for signals was not tried: GRT leaves M6 / M7 at 4-6 % usage, so upper-layer capacity is not what is missing.

### 11.6 Hold repair at the weight-macro data inputs

Not attempted on a routed database: detailed route is not stable (70 675 markers, still -4 % per 70-min iteration),
and in this OpenROAD build a post-route ECO means a complete TritonRoute pass again (it re-routes the whole design,
~9 iterations / ~10 h here) - the precondition "only if detailed route is stable" is not met.  `pnr/hold_eco.tcl`
implements it (finish.odb + SPEF of every corner, hold uncertainty on the weight-macro CLK pins, `repair_timing
-hold`, legalise, fillers, incremental GRT, optional detailed route + finish) for a converged route.  Cause of the
violations (PT, `qa3_t5c`): all are host write data (`u_host/h1_wdata_reg`) -> weight macro D; the weight macro
clock arrives late (tt clock latency 1.68 ns at `u_wmem_o` bank 2 CLK vs 1.15 ns at the host registers: the CKBD4
balance-level buffer of section 3), so the fix belongs in CTS (a CKBD8 / CKBD16 macro clock-gate cluster) rather
than in 150 delay cells.  The path is used only when the host loads the weights.

### 11.7 Conclusion

The v3 detailed route does not converge with density / padding / margin changes because its markers come from one
place, the centralised act-buffer -> xbar -> PE hub at the centre of the band, whose wiring (3 072 act read-data bits
in, a 128-b window broadcast to 64 PEs out, through ~200 x 500 um) exceeds what M2-M7 can carry there once pin access
is accounted for: unpadded, GRT sees no overflow but detailed route leaves ~70 k M2 / M3 shorts there; padded by 2
sites, GRT itself overflows there.  What would help is architectural / floorplan: splitting the xbar per PE column
group (or per act-buffer row) so the read data does not converge on one spot, or a wider band only around the hub
with M8 signal tracks over it - not attempted in this time box.

## 12. Commands

```bash
# this revision (section 11): diagnosis, placement experiments, route of record qa3_t5c
QC_FLOW=$PWD/flow/tsmc65 QC_PNR_OUT=$QC_BUILD/pnr/qa3_t5b QC_BUILD=$QC_BUILD openroad -exit qc18acc/pnr/gr_diag.tcl     # GRT -verbose + tile utilisation
QA_STEP=place QA_NO_GRT=1 QC_FLOW=... QC_PNR_OUT=<run> openroad -exit qc18acc/pnr/gr_diag.tcl                        # tiles only
QA_V=3 QA_CFG=qc18acc/pnr/qa3c.cfg qc18acc/pnr/run.sh pnr qa3_t5c                      # hub pad 1 (QC_PNR_SET="QA_HUB_PAD 2": qa3_u5d)
gdb -p <openroad pid> -batch -ex "set var *(int*)0x4644e98 = 8"                         # drt::END_ITERATION (symbol address, this binary)
QA_V=3 QA_IO_REF=1 qc18acc/pnr/run.sh pt qa3_t5c
QA_V=3 qc18acc/pnr/power.sh -H tau5 -t qa3_t5c 3.7 && QA_V=3 python3 qc18acc/pnr/report.py 3.7 qa3_t5c
QA_V=3 qc18acc/gls/run_gls.sh start tau5 qa3_t5c_pnr 0 1
# v3 baseline (v2 recipe) and v3 improved, on the P&R host in /tmp/$USER/qc18acc/repo:
QA_V=3 qc18acc/pnr/run.sh pnr qa3_t1
QA_V=3 QA_CFG=qc18acc/pnr/qa3b.cfg qc18acc/pnr/run.sh pnr qa3_t5b             # (run used QA_BAND=950 + QC_PNR_SET, = qa3b.cfg)
QA_CFG=qc18acc/pnr/qab.cfg qc18acc/pnr/run.sh pnr qa_t1b                      # v2 improved
QA_V=3 qc18acc/pnr/run.sh pt qa3_t1;  QA_IO_REF=1 QA_V=3 qc18acc/pnr/run.sh pt qa3_t5b;  QA_IO_REF=1 qc18acc/pnr/run.sh pt qa_t1b
QC_FLOW=$PWD/flow/tsmc65 QC_PNR_OUT=$QC_BUILD/pnr/qa3_t5b QC_BUILD=$QC_BUILD openroad -exit qc18acc/pnr/ant_check.tcl > ant.out
# locally:
QA_V=3 qc18acc/pnr/power.sh -H tau5 -t qa3_t5b 3.4 && QA_V=3 python3 qc18acc/pnr/report.py 3.4 qa3_t5b
QA_V=3 qc18acc/pnr/power.sh -H tau1 -t qa3_t1 5.6  && QA_V=3 python3 qc18acc/pnr/report.py 5.6 qa3_t1
qc18acc/pnr/power.sh -H usask -t qa_t1b 3.9 && python3 qc18acc/pnr/report.py 3.9 qa_t1b
ssh tau5 'B=/tmp/ckp908/qc18acc/build; mkdir -p $B/syn/qa3_t5b_pnr; cp $B/pnr/qa3_t5b/out/qa_top.v $B/syn/qa3_t5b_pnr/'
QA_V=3 qc18acc/gls/run_gls.sh start tau5 qa3_t5b_pnr 0 1; QA_V=3 qc18acc/gls/run_gls.sh check tau5 qa3_t5b_pnr
# experiments (section 3): grt_only.tcl from a copy of a run dir with db/cts.odb, settings via QC_PNR_SET, e.g.
QC_FLOW=$PWD/flow/tsmc65 QC_PNR_OUT=<dir> QC_BUILD=$QC_BUILD QC_PNR_SET="QA_IO_REF 1" openroad -exit qc18acc/pnr/grt_only.tcl
```
