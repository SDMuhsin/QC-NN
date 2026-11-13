# Column slice, third P&R probe: PE-row placement control

Labels as `results/pnr_slice2.md`: **[S]** static (DC / P&R geometry, PrimeTime with the def2spef SPEF, or OpenROAD's
own estimate, marked [OR est.]); **[R]** reasoning from [S] numbers; **[M]** bench.  Tools: DC 2024.09 topographical,
OpenROAD 2.0-12381, PrimeTime Q-2019.12; hosts tau5 / usask, build tree `/tmp/ckp908/qc18bacc/build`.  Baseline: slice v2
`qcs2_a` (`qb_col_cwfp`, 702 344 um2, 279 MHz post-GRT [OR est.], rows 9-15 scrambled).

Placement metric (`qb3_stats`, logged after gpl and after the first legalisation): per PE row, the placed y-centroid,
the 10-90 % y span, and the fraction of cells within the row's band +- 0.25 band ("in-band").  "In order" means
monotone centroids, rows 0-15.  Band height is 116-119 um.

**Answer.**
- **No method keeps every PE row both in order and compact without destroying timing.**
  - Region fences (a) are not honoured in this build.
  - No gpl setting (b) holds the v2 netlist's rows: it mixes them whatever the start.
  - The scripted per-row remap (c) gives perfect order, but legalisation then costs +56-66 % HPWL and the PE rows
    fall to -2 to -5 ns at placement.
- **Mechanism (measured):** with CREG, each broadcast-register fan-out net spans several PE rows of its 8-row group:
  either a BR Q pin directly, or DC's core-level fan-out inverters / buffers.  Every pair of rows in a group then
  shares 270-500 nets, so the placer treats the group as one cluster.
- **(d) one BR per row pair** (`qb_core #(BRG 2)`) removes those trees and costs +2.5 % DC area (bench-exact).
  - Pairs stay in order; the two rows of a pair co-place.
  - With an incremental gpl after the DRV repair (`QB_INC_POST`), every row centroid is in order. Rows are still not
    compact: pairs interleave over up to 400 um.
  - This removes the real limiter, legalisation drift. Post-CTS setup after repair and legalisation is -0.009 ns
    (v2: -0.576 ns).
- **Result (`qcs3_b2i`):**
  - post-GRT 461.5 MHz tt [S, OR est.] (WNS -0.167 ns at 2.0 ns), vs 279 MHz for v2;
  - routed PrimeTime SPEF reg2reg **472.8 / 290.3 MHz tt / ss** [S], hold reg2reg -0.001 / +0.031 ns;
  - **not DRC-clean**: 9 130 markers after 5 detailed-route iterations (the box limit; 240 k -> 142 k -> 134 k ->
    18 k -> 9 k);
  - core / DC 1.421, die / DC 1.469. The core area is the same 1.023 mm2 as v2; v2 was 1.456 / 1.506 against its
    smaller DC area.
- **New critical path:** post-GRT, the wide lane (-0.17 ns), with every PE row at -0.13 ns or better.  Routed, the PT
  limiters are the f_src control fan-out to the fused lanes (tt) and BR -> popcount (ss).  The PE S2 accumulator is gone
  from the top.
- **Not done:** a DRC-clean route.  It needs more DR iterations: v1 / v2 / here, roughly 15 min per iteration on this
  strip.

## 1. What this OpenROAD build supports (step 1) [S]

| item | result |
|---|---|
| newer binary | none.  2.0-12381-g01bba3695 (Feb 2024) is the newest `openroad` on litex-hub.  conda-forge has no package, and there is no docker / apptainer on tau5 |
| `global_placement -skip_initial_place` | yes (it sets initial-place iterations to 0).  Slice v1 / v2 already used it from the band seed |
| `-init_density_penalty`, `-density`, `-pad_left/-pad_right` | yes, but global only: no per-group density or padding in gpl.  DPL has `set_placement_padding -instances` (legalisation only) |
| region / fence in gpl | `create_voltage_domain` and plain dbRegion / dbGroup are ignored (v1 test).  This build does build one `PlacerBase` / `NesterovBase` per **power-domain group** (`dbPowerDomain` -> `dbGroup` -> `dbRegion`, odb Tcl API), so that path was tested as method (a) |
| DPL groups | present (`Opendp::groupAssignCellRegions` etc.); not needed once (a) failed |

## 2. Placement-control methods (step 2), after gpl / after DPL [S]

All on `qb_col_cwfp` (v2 netlist) unless marked b2.  Place WNS = OpenROAD tt at placement parasitics, all paths, after DRV repair + DPL.

| run | method | inversions | max row span y10-90 um | min in-band | place WNS ns | verdict |
|---|---|---|---|---|---|---|
| v2 `qcs2_a` (gpl dump) | band seed + TD gpl (default penalty 8e-5) | 2 | 584 | 0.14 | -0.614 | baseline: rows 9-15 mixed |
| `qcs3_reg` | (a) 16 power-domain regions = row bands | 8 | 425 | **0.000** | n/a | **not honoured**: with TD, the region solvers never converge (overflow 0.9997 after 1 070 iterations, stopped).  Without TD (capped at 500 iterations), cells pack into x 10-74 um and out of their bands (rows 1 and 7: 0 % in band) |
| `qcs3_pen` | (b) band seed, `-init_density_penalty 0.01` | 2 | 982 | 0.26 | -0.048 | out of order (rows 10, 11, 14) |
| `qcs3_ntd` | (b) band seed, non-TD gpl | 2 | 753 | 0.22 | -1.376 | out of order: TD weighting is not the cause |
| `qcs3_dt` | (b) + decoder band at the top (`QB_DEC_TOP`) | 3 | 546 | 0.19 | -0.424 | out of order |
| `qcs3_g2a` / `g2b` | (b) from the remapped, spread placement, penalty 0.01 / 0.001 | 2 / 2 | 983 / 614 | 0.28 / 0.14 | | converges back to the v2 mixing (row centroids within 2 um of the seeded run) |
| `qcs3_rinc` | remap, then `global_placement -incremental` | 3 | 581 | 0.26 | | re-mixed |
| `qcs3_remap` | (c) gpl, then every PE row is mapped into its band by y rank (x kept), DRV repair + DPL only | **0** | 142 | 0.92 | **-5.438** | in order, but legalisation +56 % HPWL (avg 16 um, max 328 um displacement): PE15 -5.44, decode/BR -2.95, rows 1/2/8/14 -2.0 to -2.4 |
| `qcs3_rx` | (c) + x by rank (uniform over the width) | 0 | 184 | 0.84 | -4.340 | same (+56 % HPWL) |
| `qcs3_b2` | (d) **BRG 2** netlist, band seed + TD gpl (v2 recipe) | 1 (rows 2 / 3 of one pair, 4 um) | 508 | 0.29 | **-0.255** | **pairs in order**, rows of a pair co-placed; pairs (2,3)/(4,5) and (10,11)/(12,13) overlap |
| `qcs3_b2r` | (d) + (c) remap | 0 | 184 | 0.83 | -3.84 (class) | in order, timing lost to legalisation (+66 % HPWL) |
| `qcs3_b2g` | (d) + remap + second gpl (penalty 0.01) | 1 | 600 | 0.26 | | gpl re-mixes the pairs |
| **`qcs3_b2i`** | (d) + incremental gpl (`-density 0.85`) after the DRV repair, before the first legalisation (`QB_INC_POST`) | **0** | 509 | 0.29 | -0.348 | **centroids in order and pairs kept, but not compact**: rows 2-5 interleave over y 1 448-1 851 and rows 12 / 13 overlap 10 / 11 |
| `qcs3_b2d` | (d) + gpl `-density 0.72` (stopped for b2i) | 1 | 505 | 0.31 | | |

## 3. Mechanism of the scrambling [S]

Net count between cell classes in the flat netlist (OpenROAD, floorplan db; a net is counted once for each pair of
classes it connects):

| netlist | PE row <-> PE row of the same BR group | PE r <-> PE r +- 4 (drain chain) | BR g -> one PE row |
|---|---|---|---|
| v2 (`BRG` 8, CREG) | **all-to-all inside each 8-row group: 270-500 nets per pair** (28 pairs per group) | 160-163 | 140-200 (BR0), 243-364 (BR1) |
| b2 (`BRG` 2) | only the pair partner: 518-521 | 162-163 | 321-477 |

With CREG the BR Q pins drive the popcount logic of all 8 PEs directly, so each BR net spans several rows.  In rows
8-15 alone, 1 959 nets reach 2 or more rows:
- 621 driven by core-level INVD1 and 144 by CKBD1, i.e. DC's fan-out inverters / buffers between BR and PEs, each
  feeding 2 rows;
- 121 + 81 BR `c_q` / `t2_q` registers driving all 8 rows directly;
- 640 drain-chain `shd` nets (row r -> r - 4).  For the placer, each 8-row group is
therefore one strongly connected cluster (~10 k inter-row nets), held to its band only by 288 act pins per row on the
left edge.  Global placement contracts each group: rows 8-15 collapse towards their common centre and mix.  This
happens with every start (seed boxes, spread remap, incremental), with any density penalty, and with or without
timing weighting.  In the v2 gpl, the decoders and CREG port registers also go to the top edge, next to the cd / ctl
pins (median y 3 042 of 3 105), and both BRs follow them (median 2 798 / 2 831).

Splitting the BR per row pair (b2) removes the cross-row trees.  Pairs then stay in order, but the two rows of a pair
merge (they share a BR), so rows are ordered only at pair granularity.  Forcing order after gpl (remap) breaks the
placement: the rows had been interleaved at ~50 % density, compressing each into its band doubles the local density,
and legalisation then moves cells 16-20 um on average, up to 330 um (+56-66 % HPWL).

## 4. RTL option (d): `qb_core #(BRG)` [M, S]

`BRG` = PE rows per broadcast register (default 8 = R1 / v2, unchanged).  The BRs are duplicated, with no logic or
latency change.  New top `qb_col_cwfp_b2` = `qb_col_cwfp` + `BRG 2` (8 BRs per column instead of 2).  Bench define
`QBC_BRG`.

| check | result |
|---|---|
| bench `QBC_DEFS="-DQBC_CREG=1 -DQBC_WTP=1 -DQBC_FTP=1 -DQBC_PPOP=1 -DQBC_BRG=2"`, vectors `exp2/core/img0`, `img1` (those of pnr_slice2.md) | **PASS**: 3 644 / 3 684 cycles, 630 784 words each, 0 errors [M] |
| same defines without `QBC_BRG` (default 8 = the pnr_slice2.md netlist), img0 | PASS, 3 644 cycles, 0 errors [M] |
| DC topo, 1.65 ns | **719 763 um2** (+17 419, **+2.5 %** vs 702 344); 25 823 regs (+3 096 = 6 x 516); pre-route PT 601.0 / 384.5 MHz tt / ss (v2 600.7 / 385.2) [S] |

## 5. Full flow on the best method: `qcs3_b2i` = (d) + `QB_INC_POST` [S]

Recipe as v2 (`slice.cfg`): strip 330 x 3 100 um core, P&R at 2.0 ns, band seed + TD gpl, DRV repair, then
`QB_INC_POST` (incremental gpl at density 0.85), DPL, `QB_REPIN 2`, CTS.  Then one setup repair and one hold repair,
each legalised (`QB_RT_LOOPS 0`).  Then GRT (`GR_ADJUST` 0.15) and DR.  The same `cts.odb` was routed twice:
`qcs3_b2i` on usask with 2 DR iterations, and `qcs3_b2i` on tau5 with 5 iterations (`QB_DR_ITER`).

| quantity | `qcs3_b2` (d), no INC_POST | **`qcs3_b2i`** | v2 `qcs2_a` | label |
|---|---|---|---|---|
| DC cell area (1.65 ns) | 719 763 um2 | 719 763 um2 | 702 344 | [S] |
| row order after DPL (inversions / max span / min in-band) | 1 / 508 um / 0.29 | **0 / 509 um / 0.29** | 2 / 584 / 0.14 | [S] |
| place WNS (all paths) | -0.255 | -0.348 | -0.614 | [S, OR est.] |
| CTS legalisation max displacement | 106 um | | | [S] |
| post-CTS WNS before repair | -0.642 | **-0.381** | -0.831 | [S, OR est.] |
| after setup repair + legalisation + hold repair + legalisation | -0.412 | **-0.009** | -0.576 | [S, OR est.] |
| cell area end / utilisation | 824 587 um2 / 0.806 | 823 293 / 0.805 | 824 768 / 0.806 | [S] |
| post-GRT reg2reg WNS (fmax) | -1.773 (265 MHz) | **-0.167 (461.5 MHz)** | -1.586 (279) | [S, OR est.] |
| post-GRT hold | -0.082 | +0.019 | -0.283 | [S, OR est.] |
| post-GRT worst per class | PE6 -1.77, PE7 -1.29, others >= -0.23 | wide lane -0.17, PE10 -0.13, PE5 / 14 -0.12, fused -0.11, dec/BR -0.10 | PE11 -1.59 | [S, OR est.] |
| routed, 2 DR iterations (usask) | | 133 734 DRC markers; PT SPEF reg2reg **470.3 / 289.4 MHz tt / ss**, hold reg2reg -0.000 / +0.032 | not routed | [S] |
| **routed, 5 DR iterations (tau5)** | | **9 130 DRC markers**; PT SPEF reg2reg **472.8 / 290.3 MHz tt / ss**, hold reg2reg -0.001 / +0.031; tt path: the `fs_q` (f_src) control register fanning out to the fused-lane input muxes (0.41 / 0.26 pF nets); ss path: BR7 `c_q` -> PE14 popcount | | [S] |
| core / die vs DC | 1.421 / 1.469 | **1.421 / 1.469** | 1.456 / 1.506 | [S] |

Notes:
- **Why `qcs3_b2` failed and INC_POST fixes it.**  `qcs3_b2` is limited by the PE 6 S2 accumulator.  At placement the
  path cells sit within 30 um of each other.  The CTS legalisation moved them 60-70 um, and the post-CTS legalisations
  another 65-90 um, along the right edge (x 322-330 um).  D1 gates then drive 0.07-0.10 pF.  The local utilisation
  there (50 um x 110 um bins) is 0.95-0.97 after CTS, against 0.80 for the whole strip.  Cause: gpl spreads the cells
  to density 0.75 *before* the DRV repair adds 13 % cell area, concentrated where the violating nets are.
  INC_POST re-spreads after the repair (max displacement 25 um, +6 % HPWL).
- **Hold.**  All PT hold violators (8 443 endpoints) are input paths (`pf` -> parameter bank) under the ideal-clock IO
  delays of the SDC, a known pessimism (pnr_slice.md).  Reg2reg hold is met at both corners.
- **Annotation.**  7 469 of 251 320 nets are not annotated in PT; the ones listed are driverless `SYNOPSYS_UNCONNECTED` nets.
- **Global route** was clean on the first try with `GR_ADJUST` 0.15.  0.25 was not tried.
- **Detailed-route convergence.**  tau5: 240 k -> 142 k -> 134 k -> 18 k -> 9.1 k after iterations 0-4, at ~12-15
  min per iteration.  v2 had 127 k after 4.  The two routes (2 vs 5 iterations, 134 k vs 9.1 k markers) give the same
  PT tt within 0.5 %.  So the fmax does not hinge on the unfinished DRC [R], but 9 k markers is still not sign-off.

## 6. Files

`impl/pnr/slice3.cfg` (= slice.cfg + `slice3_place.tcl` + `slice3_post_grt.tcl`).

`impl/pnr/slice3_place.tcl` sets the method and its options:
- `QB_PM` seed | region | remap | script;
- `QB_REMAP_X`, `QB_REMAP_BR`, `QB_REMAP_INC`, `QB_REMAP_GPL`, `QB_NESV_ITER`, `QB_DPL1_ARGS`;
- `QB_GPL_DUMP` / `QB_GPL_FROM` (reuse a gpl);
- `QB_BRG`;
- the per-row statistics and the per-class WNS.

`impl/pnr/slice3_post_grt.tcl` gives reg2reg and per-class WNS at global-route parasitics.

`impl/pnr/slice_bands.tcl` gains the `QB_DEC_TOP` option (default off).

RTL: `hw/rtl/qb_core.sv` (`BRG`), `hw/rtl/qb_col.sv` (`qb_col_cwfp_b2`).  Bench: `hw/tb/tb_qb_core.sv` (`QBC_BRG`).

```bash
QBC_TAG=_b2 QBC_DEFS="-DQBC_CREG=1 -DQBC_WTP=1 -DQBC_FTP=1 -DQBC_PPOP=1 -DQBC_BRG=2" qc18bacc/hw/tb/run_tb_core.sh build
QBC_TAG=_b2 qc18bacc/hw/tb/run_tb_core.sh run /tmp/root/qc18bacc/exp2/core/img0 /tmp/root/qc18bacc/exp2/core/img1
QC_TOPO=1 QC_HOOK=$PWD/qc18bacc/impl/hooks/topo_strip.tcl QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" \
    qc18bacc/impl/run.sh all qb_col_cwfp_b2 1.65 qb_col_cwfp_b2_tt_p1.65_topo
QB_CFG=slice3.cfg QB_TOP=qb_col_cwfp_b2 QB_SYN=qb_col_cwfp_b2_tt_p1.65_topo QB_BRG=2 QB_PM=seed QB_PNR_PERIOD=2.0 \
    QB_REPIN=2 QB_RT_LOOPS=0 QB_GR_ADJ=0.15 QB_DR_ITER=4 qc18bacc/impl/pnr/run.sh pnr qcs3_b2
QB_PT_PERIOD=2.0 qc18bacc/impl/pnr/run.sh spef qcs3_b2; QB_PT_PERIOD=2.0 qc18bacc/impl/pnr/run.sh pt qcs3_b2
```
