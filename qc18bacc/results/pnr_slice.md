# One column slice of qb_core through DC topographical + OpenROAD (strip floorplan, timing-driven placement)

Labels: **[S]** static: synthesis / P&R geometry, PrimeTime (PT) with the def2spef SPEF, or OpenROAD's own estimate
where marked "OR est."; **[R]** reasoning / estimate derived from [S] numbers.  Tools: DC 2024.09 (topographical,
`-spg`), OpenROAD 2.0-12381 (flow `flow/tsmc65/pnr`, unchanged) + design scripts `qc18bacc/impl/pnr/slice*`,
PrimeTime Q-2019.12.  Hosts: tau5, usask (tau-02); kit-derived views stay in `/tmp/ckp908/qc18bacc/build`.
Previous probe: `results/pnr_core.md` (8 x 2 proxy `qb_core_s`, WLM netlist, square die, not timing-driven).

**Stop-rule status.**  Detailed route of the main run `qcs_t1` did **not complete**: DRC markers 252 k -> 122 k -> 115 k
-> 35 k -> 14.3 k -> 7.9 k -> 5.3 k -> 4.4 k -> 3.6 k -> 2.6 k -> **940** after iteration 10 of 20, then the router
**crashed (SIGSEGV in `drt::FlexDRWorker::main`) at the start of iteration 11**, 1 h 51 min after the restart from the CTS checkpoint;
no routed checkpoint is written before the end of detailed route, and a re-run (~2 h) did not fit the box.  So there is **no routed SPEF / PrimeTime number**: the last
completed stage is **post-global-route** (OpenROAD placement + global-route parasitic estimates, reg2reg, tt only;
on the 8 x 2 proxy these estimates bracketed the routed PT number within 0.12 ns, pnr_core.md 2.1).  Every number
below is labelled with its stage.

**Answer.**  One column (16 PEs + 36 decoders + BR + 32 fused + 4 wide lanes, 696 k um2 topographical DC) placed on a
330 x 3 100 um strip: **366 MHz tt post-GRT [S, OR est.]** (WNS -0.730 ns at 2.0 ns; ~230 MHz ss [R, x0.63 = the
pre-route ss / tt ratio]), **core / DC 1.47, global-routed** (die 1.057 mm2; cells x1.17 after repair, utilisation
0.796), global route clean, detailed route converging (940 DRC markers at iteration 10) until the router crashed.  Versus the 8 x 2 proxy of
pnr_core.md (WLM, square, not timing-driven): fmax **+18 % at the same stage** (post-GRT est. 366 vs 311 MHz; the
proxy's routed PT was 322.5 MHz), routed factor 1.665 -> 1.47, and the fused-lane repeater-chain mechanism is gone; the limiters are now
logic-depth paths inside the wide lane, the PE popcount and the fused-lane tail (wire share < 5 %) plus 0.4 ns of
clock skew.

## 1. Slice and setup

**Slice** = `qb_col` (`hw/rtl/qb_col.sv`, new thin wrapper) = `qb_core #(.ROWS(16), .COLS(1))`: one full column of
the 16 x 8 core, i.e. 16 PEs (rows 0-15), the column's 36 decoders + NNw (`qbc_coldec`), its 2 broadcast registers
(one per 8-row group), its 32 fused lanes (PE rows 0-3 x 8) and 4 wide lanes, and its share of the parameter banks
(8 fused + 8 wide channel records; the common mode bits, shared by the 8 columns in the full core, are replicated).
`qb_core` has the column hierarchy already (generate `g_col` / `g_r.g_c` / `g_fq.g_fc.g_fi` / `g_wq.g_wc`), so
`qb_core.sv` is **unchanged**; R1 bench re-run: `run_tb_core.sh` on E6_s0 val 0 (fresh export) **PASS**, 3 644 cycles,
630 784 words compared, 0 errors [S].

| item | value |
|---|---|
| synthesis | `impl/run.sh all qb_col 2.0`, tt compile, 2.0 ns, 20 % IO delay, max transition 0.2 ns. **Topographical** (`QC_TOPO=1`, Milkyway `tcbn65gplus` frame + TLU+ typical, `compile_ultra -no_autoungroup -gate_clock -spg`) with the strip context (`impl/hooks/topo_strip.tcl`: utilisation 0.70, aspect 8.8, port sides as the P&R pins).  Reference: the same top in WLM mode (WireAreaLowkCon enclosed, as R1) |
| floorplan | strip, core **W 330 x H 3 100 um** (die 340 x 3 110), utilisation 0.681 of the topo cell area; variant `qcs_t6` W 375 (0.599).  Bands bottom-up (`slice_bands.tcl`, from the netlist areas): lane band 1 159 um (32 fused + 4 wide lanes, both parameter banks, PPU control registers), then PE row r = 0..15 in 121.3-um bands; PDN flow default |
| IO pins (7 746: 6 959 in, 787 out) | **left**: act row r (288 b) + b2 row r inside PE row r's band (`slice_pins.tcl`); **top**: cd, ctl, t2, clk, rst_n, b2_vld (codes enter at the top and are broadcast down); **bottom**: lane stream (s_rd, f_y, f_b, w_r, w_y, w_b), parameter banks (pf, pw), PPU controls (where the S macros / parameter store sit under the lane band); M3/M5 left, M4/M6 top/bottom, 1-track pitch |
| placement guides | **region fences do not work in this OpenROAD build's global placement**: a `dbRegion` + `dbGroup` fence and a `create_voltage_domain` group were tested on the 8 x 2 proxy: 0 of 6 131 member cells inside the box after gpl [S].  The bands are therefore imposed as a **seed**: every cell starts at its band centre (PE r: band r; lanes / banks / glue: lane band; BR g: rows 8g..8g+7; decoders between the groups), gpl runs `-skip_initial_place` from it (`slice_place.tcl`) |
| global placement | **timing-driven ON** (`-timing_driven`, default reweighting), not routability-driven, target density 0.75, no padding |
| DRV repair | `REPAIR_DESIGN auto` = `repair_design` on the violating nets only (all other nets dont_touch), then detailed placement |
| CTS | `-balance_levels -sink_clustering_buffer CKBD4` (DC clock gates kept) |
| post-CTS (`slice_post_cts.tcl`) | IO delays shifted by the insertion delay (input + 0.85 ns, output - 0.85 ns: the neighbours are on the same tree; without it 8 016 IO hold violations, worst -0.65 ns), then `repair_timing -setup` (margin 0, all violating endpoints), `repair_timing -hold` (margin 0.02 ns, <= 10 % buffers), legalisation, and a second setup + hold repair round after legalisation (`QB_RT2`, not in `qcs_t1`) |
| corners | P&R optimisation at **tt**; sign-off PT tt / ss with SPEF planned (not reached, see status) |
| route | `GR_ADJUST` 0.25, detailed route up to 20 (t1) / 14 (t6) iterations, no antenna repair (segfaults in this build) |

## 2. Runs

| run | netlist | strip (core) | placement | post-CTS repair | furthest stage |
|---|---|---|---|---|---|
| `qcs_w1` | **WLM** (669 457 um2) | 330 x 2 980 (0.681) | band seed + TD gpl | flow `cts.tcl` repair (IO delays not shifted): hold repair hit `MAX_UTIL` after 57 895 buffers; restarted, stopped in the setup repair | CTS (WLM-vs-topo reference) |
| **`qcs_t1`** | **topo** (696 140 um2) | 330 x 3 100 (0.681) | band seed + TD gpl | setup, hold, legalise | post-GRT estimates; detailed route 940 DRC after 10 of 20 iterations, then DRT crash (SIGSEGV) |
| `qcs_t2` | topo | 330 x 3 100 | + lane compaction in place | - | place: **DPL-0036** (legalisation of the overlapping compacted lanes failed) |
| `qcs_t3`, `qcs_t5` | topo | 330 / 375 x 3 100 | + lanes compacted into non-overlapping slots, legalised before the DRV repair (t5) | - | place: **WNS -6.5 / -5.6 ns** (legalisation of the compacted blocks: HPWL +29 %, lane-internal nets 150-300 um, 0.5-ns slews) |
| `qcs_t6` | topo | **375** x 3 100 (0.599) | band seed + TD gpl | setup, hold, legalise, setup + hold again | post-CTS repair; **global route failed** (GRT-0119, horizontal overflow at the left edge, y 2.5-2.8 mm: act pins of PE rows 11-14) |

## 3. Results (`qcs_t1` unless noted)

| quantity | slice `qb_col` (this, topo + strip + TD) | `qb_core_s` 8 x 2 (pnr_core.md, WLM, square, not TD) | label |
|---|---|---|---|
| content | 16 PE, 36 dec, 2 BR, 32 fused + 4 wide lanes, 8 + 8 records | 16 PE, 72 dec, 4 BR, 64 fused + 8 wide lanes, 16 + 16 records | |
| DC cell area | **696 140 um2** topo (179 424 cells); WLM 669 457 (+4.0 % topo) | 921 629 (WLM) | [S] |
| pre-route fmax tt / ss (PT) | topo (DC topo parasitics) 495.7 / 311.9 MHz; WLM 500.5 / 316.2 | 500.4 / 316.6 | [S] |
| die / core | 340 x 3 110 = **1.057 mm2** / 330 x 3 100 = 1.023 mm2 | 1.586 / 1.535 mm2 | [S] |
| cell area place / CTS / after repair (x DC) | 778 421 (x1.118) / 803 771 (x1.155) / **814 086 (x1.169)** | 1.040 (x1.128) / 1.076 (x1.168) | [S] |
| DRV-repaired nets at place | 9 833 (WLM netlist, same recipe: 12 484) | 7 649 buffers | [S] |
| utilisation | 0.681 floorplan, 0.761 place, **0.796** after post-CTS repair | 0.60 -> 0.70 | [S] |
| routed factor core / DC | **1.469** at global route (DR incomplete; core / WLM DC: 1.528; die / DC 1.519) | 1.665 (routed) | [S] |
| global route | clean (no overflow), 8.63 m wire after DR iteration 3 | clean | [S] |
| detailed route / DRC | **not completed**: 940 markers after 10 iterations (M2 shorts dominated early), then DRT SIGSEGV in iteration 11 | 14 iterations, 58 markers | [S] |
| **fmax reg2reg tt** | **366 MHz post-GRT** [OR est.] (WNS -0.730 ns) | 322.5 MHz routed (PT + SPEF); post-GRT est. there 1.211-ns WNS = 311 MHz | [S] |
| fmax ss | ~230 MHz [R] (pre-route ratio x0.63; no ss in the P&R corners) | 201.5 MHz routed (PT) | [R] / [S] |
| critical path (tt) | wide lane S3 `g_wq_1 u_lw/r2_reg_10_ -> b_o_reg` (41 stages, 2.47 ns) | fused lane `u_rlate -> u_rout` (71 stages, 34 repeaters) | [S] |
| wire share of the critical path | net RC 0.2 %, + P&R repeaters 2.0 % (1 buffer) | net 1.7 %, + repeaters 38 % | [S, OR est.] |
| hold (tt, reg2reg) | +0.019 post-CTS repair; -0.027 post-GRT (TNS -0.21) [OR est.] | PT -0.012 (no hold repair) | [S] |

### 3.1 Timing through the flow (tt, reg2reg except where noted; OpenROAD estimates) [S, OR est.]

| stage | `qcs_t1` topo | `qcs_w1` WLM (same recipe) | `qcs_t6` topo, W 375 |
|---|---|---|---|
| place | -0.638 ns (TNS -143) | **-1.592** (TNS -596) | -0.991 |
| CTS (IO delays shifted, before repair) | -1.004, 1 489 endpoints; hold -0.114, 63 endpoints | -2.318, 2 371 endpoints (IO not shifted: hold -0.649, 8 016 endpoints) | -1.287, 1 414 |
| after `repair_timing -setup` | **-0.267**, 494 endpoints | (stopped) | **-0.160**, 428 |
| after hold repair + legalisation | -0.526, 966 (hold 0) | | -1.672, 962 |
| after second setup + hold round | (not run) | | -1.667, 1 127 |
| post-global-route (`grt_est.tcl`, from the repaired checkpoint) | **-0.730 ns -> 366 MHz** (TNS -170) | | GRT failed |
| post-GRT worst per class | PE -0.536 (`g_r_14` popcount), fused lane -0.542 (`u_rlate -> u_rout`), wide lane -0.730 (`r2 -> b_o`) | | |
| clock latency / skew (post-GRT est.) | 0.76-1.16 ns / 0.40 ns | 0.73-1.06 / 0.33 | |

PrimeTime with SPEF (tt / ss, zero-wire comparison via `pt_diag.tcl`) was **not run**: no routed DEF inside the
time box (stop rule; DRT crash).  The scripts are ready (`run.sh spef` / `QB_PT_DIAG=1 run.sh pt`) for `qcs_t1` once its
detailed route completes.

## 4. Critical-path mechanism

**WLM vs topographical netlist, same placement recipe** [S]: with the WLM netlist the placed critical path is again
the fused lane `u_rlate -> u_fin -> u_rout` (`g_fq_1 g_fi_6`), stretched **840 um** down the lane band (u_rlate at
y 1 258 um next to the PE row-1 shadow, u_rout at y 418 um towards the stream pins) and buffered by a **49-buffer
`wireN` chain** placed every ~15 um along the net (27 ps per stage, ~1.4 ns of the 4.0-ns data path): post-CTS WNS
-2.318 ns.  With the topographical netlist and the identical strip / seed / TD placement the long chains are gone:
every class's worst post-GRT path has **at most one P&R buffer** and net RC is 0.2-1.5 % of the delay.  The
topographical netlist (+4 % cell area) needs 21 % fewer DRV
repairs (9 833 vs 12 484 nets) and gains 0.95 ns at placement (-0.64 vs -1.59 ns).

**What limits `qcs_t1`** [S, OR est.]: the post-GRT critical path is the wide lane's S3 stage
(`g_wq_1 u_lw/r2_reg -> b_o_reg`: 20-b `y2 + r2` ripple adder of FCICIND1 carry cells -> +-32767 saturation ->
21-b compare -> b_o), 41 stages, 2.47-ns data path, 0.002 net / 0.020 net+repeater share; the PE popcount
(`g_r_14 u_in/c_q -> u_pop/s_q`, 20 stages, 2.27 ns) and the fused-lane tail (`u_rlate -> u_rout`, 43 stages,
2.25 ns) are within 0.2 ns of it.  These are logic-depth paths that DC sized to just meet 2.0 ns (DC recovers area
until every path meets); after placement the same cells see the real pin + wire loads and the clock skew of a
3.1-mm tree (0.40 ns, latency 0.76-1.16 ns), and the post-CTS `repair_timing` gain (-1.00 -> -0.27 ns) is half
lost again when the hold repair's legalisation moves the upsized cells (-0.53 ns; t6: -0.16 -> -1.67 ns).
Wire share by delay on these paths [S, OR est.] (`wire_share.py`, post-GRT): net RC 0.2-1.5 %, P&R repeaters
1.8-3.1 % (one buffer each); the remaining increase over DC is cell delay under real loads and slews (not separable
without the PT zero-wire re-timing, not run).

**Bands** [S]: the seed keeps PE rows 0-10 in their bands (0.82-1.00 of the cells within +-0.5 band after gpl) but
rows 11-15 only at 0.69-0.77 (the upper rows drift by about one band); in the W-375 strip this put the act pins of
rows 11-14 up to a band away from their PE and the left-edge horizontal capacity overflowed at global route
(`qcs_t6`).  Lane compaction (`QB_COMPACT`, t2 / t3 / t5) was a negative result: the legaliser cannot place compacted
lane blocks without either failing (DPL-0036) or spreading them by hundreds of um (HPWL +29 %, place WNS -5.6 ns).

## 5. What would raise fmax further [R]

1. **Fixed placement of the lanes and the upper PE rows instead of a seed** (the measured gap: region fences are
   ignored by this build's gpl): pre-place each PE row and each lane as a FIRM block before gpl (as qc18acc v4's
   `xbar_place.tcl` for the crossbar registers) and unfix after gpl; or move to a newer OpenROAD whose gpl honours
   fence regions.  This removes the row 11-15 drift (and the t6 GRT overflow) and keeps lanes compact without a
   post-hoc legalisation.
2. **Incremental legalisation inside `repair_timing`** (or a smaller-displacement legalisation pass): in this build
   `repair_timing` resizes in place and the following `detailed_placement` returns 0.25-1.5 ns of its gain.
3. **Logic of the three ~2.25-2.47-ns paths** (all inside a block, wire share < 5 %): the wide-lane S3 adder is a
   20-b ripple chain after `compile_ultra` area recovery; synthesise with a setup margin (e.g. 2.0 ns at 10-15 %
   uncertainty or 1.8 ns) or retime the saturation / compare into S3+1; the PE popcount (`c_q -> s_q`) the same
   way.  At routed-flow skew (0.4 ns) the 0.25-ns DC uncertainty is too small.
4. **Clock tree**: 0.40-ns skew / 1.16-ns latency on a 3.1-mm strip with the DC clock gates kept; a mesh or H-tree on
   the strip, or CTS without `-balance_levels` on the gated branches, would recover part of the skew.
5. **Density**: the strip routes (GRT) at 0.796 end utilisation from a 0.681 floorplan; the wider, emptier strip did
   not (left-edge pin congestion), so the act pin pitch along the strip edge (296 pins per 121-um row band on
   M3 + M5) is the density limiter, not cell area.

## 6. Files and commands

New: `hw/rtl/qb_col.sv` (+ `qb.f`), `impl/hooks/topo_strip.tcl` (DC topographical strip context),
`impl/pnr/slice.cfg`, `slice_bands.tcl`, `slice_pins.tcl`, `slice_place.tcl` (seed, band adherence, lane
compaction `QB_COMPACT` 1/2), `slice_post_cts.tcl` (IO latency shift, setup / hold repair, reports);
`impl/pnr/run.sh` takes `QB_CFG` (default `core.cfg`).  `qb_core.sv` unchanged.

```bash
# bench (local): QBC_TAG=_slicechk qc18bacc/hw/tb/run_tb_core.sh build && ... run <export_core.py img0 dir>
# synthesis (host): QC_TOPO=1 QC_HOOK=$PWD/qc18bacc/impl/hooks/topo_strip.tcl \
#   QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" qc18bacc/impl/run.sh all qb_col 2.0 qb_col_tt_p2.0_topo
QB_CFG=slice.cfg QB_SYN=qb_col_tt_p2.0_topo QB_W=330 QB_H=3100 qc18bacc/impl/pnr/run.sh pnr qcs_t1
qc18bacc/impl/pnr/run.sh est qcs_t1          # post-GRT estimates (db/cts_drv.odb = cts_rt.odb copy)
qc18bacc/impl/pnr/run.sh spef qcs_t1 && QB_PT_DIAG=1 qc18bacc/impl/pnr/run.sh pt qcs_t1
```

