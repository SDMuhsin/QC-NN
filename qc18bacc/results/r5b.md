# R5b: full-chip P&R of qb_chip (8 x qb_col_blk hard blocks + 104 ARM macros + top logic)

Labels: **[S]** static (DC / OpenROAD geometry / OpenROAD STA with placement estimates, marked [OR est.]);
**[M]** simulation; **[R]** reasoning from [S] numbers; **[E]** estimate.  Tools as R5a / R5d (DC W-2024.09-SP2
topographical, OpenROAD 2.0-12381, PrimeTime Q-2019.12).  Hosts tau6 (DC, runs t / u / v) and tau3 (block views,
runs h / w), build tree `/tmp/ckp908/qc18bacc/build`.  Time box 8 h, stop rule 4.5 h for global routing.

**Answer.**
- **Stop rule applied: no top-level global route by 4.5 h.**  No routed die area, no routed DRC count, no PT/SPEF
  fmax of the top level.  The best result is a **placed** chip (run v), section 4.
- **Blocking mechanism (measured) [S]:** the top level of this architecture is a set of chip-wide buses (host port
  `h_data` 5 189 b to every memory, act 4 608 b to the array's west edge, S read 4 096 b + lane S 4 352 b, codes 2 304 b,
  write-back 4 352 b) between macro banks and blocks that are 3-4 mm apart.  After global placement OpenROAD finds
  26-87 k long wires and > 1.2 M max-slew / fanout violations; the DRV repair adds 121-406 k buffers and doubles the
  top standard-cell area at the SDC's 0.2-ns max transition (2.4 -> 5.2 mm2, run u: utilisation > 100 %), or adds
  +2.1 mm2 at 0.4 ns (run v).  The 0.7-1-M-cell legalisation (OpenROAD detailed placement, single-threaded diamond
  search) then ran 14-40 min per attempt: two attempts were stopped unfinished, one failed at the 300-um
  displacement limit.  Each attempt cost 30-60 min; the fourth floorplan / recipe (v) was in detailed placement at
  4.5 h.
- **Die (placed, run v): 4 040 x 5 933 um = 23.97 mm2 [S]**: blocks 9.70 mm2 (40.5 %), ARM macros 6.95 (29.0 %),
  top standard cells 4.64 (19.4 %; DC 2.51 + 2.13 of DRV-repair buffers / upsizing), halos / channels / empty rows
  2.68 (11.2 %).  The compact floorplan (runs t / u, 21.62 mm2) did not fit the repaired top logic (utilisation
  > 100 %).  vs the [E] 20.16 mm2: +3.8 mm2.
- **Placement-based timing [OR est.]** (OpenROAD STA, placement parasitics, 2.0 ns, block ETMs), worst slack per
  class pre-CTS / post-CTS: top -> top -7.71 / -11.69 ns (sequencer stamp lookup; B-map write address), top ->
  block -1.08 / -6.83 (`s_rd` col 7; `t2`), block -> top -4.19 / -0.83 (`w_vld_o` -> S write data), act chain to
  column 7 -0.54 / -4.12, i.e. ~100 / 73 MHz.  Not an architectural fmax: (i) the 1-mm legalisation moves after the
  DRV repair left D0 / D1 cells driving 0.1-0.2 pF at 1-4-ns slew, (ii) TritonCTS over 24 mm2: latencies 3.5-6.2 ns,
  skew 2.68 ns.  Block-internal fmax stays R5d's routed **489.6 / 299.1 MHz tt / ss** [S].  Critical path class:
  top-level wire / legalisation (scattered sequencer logic), not block logic.
- **DC of the top logic** (1.65 ns, R4b recipe, blocks as ETMs): 2.511 mm2 logic (R5e whole-chip non-core: 2.18),
  WNS -6.94 ns, but section 2: three ETM outliers and DC topographical's own die (blocks as 0.9-mm2 obstacles)
  dominate; the CREG-2 `cd` input: 9 endpoints at -0.00 to -0.03 ns at 1.65 ns (the ETM leaves `cd_r` -> pin
  0.15-0.18 ns), i.e. at the margin, not a limiter; the qb_top decode option was not built [S].


## 1. Block views (R5d run B, tau3 `pnr/r5d_B`)

`impl/r5a/post.sh r5d_B "abs etm"` (via `impl/r5b/run.sh blk`), unchanged R5a flow [S]:
- exact-shape abstract LEF: 390 x 3 110 um, 12 356 pins, **9.25 M OBS rects (395 MB)**; antenna 0.
- ETMs tt / ss / ff (`extract_model -library_cell`; ff without an ff SPEF, not used).
- **Top-level LEF** `qb_col_blk_ring.lef` (`impl/r5b/lef_ring.py`, 2.7 MB): M1-M6 OBS = one interior rect + the exact
  rects within 1.5 um of the boundary (where every signal pin is; 0.52-um pins), M7 exact (the PG pins are M7 straps).
  Abutment / pin access checked on a macro-only test netlist with 700 act feedthrough nets between the 8 abutted
  blocks: detailed route 162 -> **0 markers** in 2 iterations [S].
- **P&R ETM copy** (`impl/r5b/etm_ins.py`): `max/min_clock_tree_path` arcs on `clk` = the block's PT register
  latencies (tt 0.96 / 0.83 ns, ss 1.47 / 1.24) for CTS `-insertion_delay` (top tree balanced with the block sinks, the
  R5a budget convention).
- **ETM outliers [S]:** 3 of 13 918 check arcs have setup > 2.5 ns: `act[1160]` 11.28 (fall), `pf[526]` 6.66,
  `act[265]` 3.15 ns, while the block's own routed PT gives act -> reg +0.528 ns slack at 2.0 ns (worst act arrival
  2.06 ns).  Extraction artefacts; excluded (false path) in the hook for later DC runs, listed separately.

## 2. Top netlist (DC)

`impl/r5b/gen.sh`: `qb_chip_tech_r5e.f` (R4b + `QB_HEAD_FW` 128) with `qb_core` replaced by `impl/r5b/core_blk.sv`
(same ports; body = `hw/tb/qb_colarr.sv`, 8 x `qb_col_blk` unresolved -> linked to the ETM).  `impl/r5b/run.sh syn`
= `impl/r4/run.sh syn qb_chip 1.65` (R4b recipe: topographical tt, `impl/r4/constraints.sdc`, `QB_MACROS_EXTRA`
R5e) + ETM dbs + hook `impl/r5b/dc_hook.tcl` (R4 hook + blocks dont_touch + clock latency -0.90 ns on the block clk
pins, so ideal-clock DC sees a tree balanced with the block sinks).

[S] (`results/r5b/dc_top.txt`, `dc_top_violators.txt`), 51 min on tau6:

| quantity | value |
|---|---|
| top logic (std cells, excl. blocks / macros) | **2.511 mm2** (act supply 0.835, sequencer 0.545, glue 0.481, prm 0.234, `u_core` wrapper 0.233 = DC buffers on the act chain, head 0.163) |
| macros | 104, 6.948 mm2 (= R5e) |
| WNS / violating endpoints | -6.94 ns / 44 761 |
| hold (DC) | -0.61 ns, 11 503 endpoints |

Violators by class (worst slack): act inputs of the blocks 15 819 (-6.94: the `act[1160]` ETM outlier; the rest is
the act chain DC buffered with CKBD12 between the blocks, as if they were apart), act line buffers 10 701 (-0.24),
block `s_rd` 4 352 (-0.86), S write data 4 096 (-0.92), sequencer queues (-1.04), head lanes (-1.38 vs 693 MHz
standalone in R5e).  Mechanism [R]: DC topographical builds its own square die with the 8 blocks as 0.9-mm2
obstacles (no floorplan), so top wires are long in arbitrary directions.  **`cd` -> block (the CREG-2 north input item of
R5d, -0.083 ns at the 0.30 P budget):** 9 endpoints, worst -0.03 ns (`cd_r` -> col 2 `cd[174]`, required 0.16 /
actual 0.19 ns at the pin): at the margin at 1.65 ns and absent from the P&R top -> block worst list (section 4), so
the qb_top decode option was not built (note: with D = 4, qb_top has no cdp stage; the port is driven by `cd_r`, the weight-macro
output register, so "decode one stage earlier" would be macro access + depth mux + 1.16-ns decode in one cycle).
A WLM DC (no placement, `QC_TOPO 0`) was started as an alternative and stopped at 40 min (WNS still 3.3e7 ns: the
enclosed top WLM on the 5 189-fanout host bus), see section 5.

## 3. Floorplan (`impl/r5b/mplace.py`, `chip.cfg`, `pdn.tcl`, `pdn_macro.tcl`)

Lower-left origin, um (run v; runs t / u: `QB_WEST` 650, `QB_SB` 250, `QB_NB` 120, die 3 790 x 5 705 = 21.62 mm2):

```
 y 5933 +-------------------------------------------------------------------------+
        | weights: 6 rows x 8 qb_w (440 x 127), R0 / MX pairs facing 40-um channels |  slot c = lanes 2c, 2c+1
   5011 |                    north logic band (200 um: cd_r, code pipeline)         |
   4811 +----------------+--------------------------------------------------------+
        | FC 3232x128    |  8 x qb_col_blk abutted (390 x 3 110 each), 3 120 wide  |
        | (R90) + 2 desc.|  act west -> east (feedthroughs), cd / ctl / t2 north, |
        | (R90), west    |  lanes / params / b2 south                              |
        | strip 900 um:  |                                                         |
        | act supply,    |                                                         |
        | sequencer, head|                                                         |
   1701 +----------------+--------------------------------------------------------+
   1301 |                    south logic band (400 um)                              |
        | img x4, prm 9  | 4 rows x 8 qb_s (rf_2p 382 x 204, R0, pins both edges)  |
        |                | B maps: 8 qb_b (MX, one per column)                      |
     10 |   params: 8 qb_p (MX, pins up), centred                                   |
      0 +-------------------------------------------------------------------------+
        0               910                                                   4040
```

- **Macros (104) + blocks (8): fixed, `MACRO_PLACE`** (`mplace.py` from the instance dump of `db/init.odb`).  Halo
  7 um: with 5 um the 10-um macro gaps left 0.4-um row slivers that pdngen could not strap (PDN-0179).
- **PDN** (`pdn.tcl` = `impl/hard/col_pdn.tcl` + M9 straps; `pdn_macro.tcl`): M1 rails, M4 / M7 straps, M8 3.0 um /
  40 um over everything incl. the blocks (M7-M8 vias onto the block M7 PG pins), M9 3.0 / 120; ARM rf: macro M4
  straps M3 -> M4 -> M7, sram M4 -> M7 and M4 -> M8 (the R90 FC's ring M4 runs horizontally).  `check_power_grid`:
  VSS true, VDD 24 unconnected M7 nodes, all on the 0.1-um block-edge PG pin slivers at the column 6 / 7 boundary
  (the block is internally connected) [S].  Took 4-9 min (pdngen) per run.
- **Pins:** 5 260 chip IOs (`h_data` 5 189 b) by `place_pins` on M3 / M4.  Signal routing M2-M9.
- **Shares of the die (run v, placed) [S]:** blocks 9.703 mm2 (**40.5 %**), ARM macros 6.948 (**29.0 %**), top
  standard cells 4.642 (**19.4 %**, of which buffers / inverters 2.032), other 2.678 (11.2 %: halos, channels,
  empty rows); row area 6.310 mm2, cell utilisation in rows 0.736.

## 4. Placement runs and the best placed result

All runs: `impl/r5b/chip.cfg` on the DC topographical netlist `syn/r5b_top`, P&R SDC from DC, 15 threads.  Run
summaries `results/r5b/runs_tuv.txt`.

| run (host) | die mm2 | recipe change | outcome [S] |
|---|---|---|---|
| t (tau6) | 21.62 | routability-driven gpl, density 0.65, SDC 1.65 ns (max transition 0.165) | gpl stalled at overflow 0.19 (5 000 iterations, 30 min); DRV repair: 1.39 M violations, **406 656 buffers**, 326 950 resized; detailed placement still in diamond search after 40 min -> stopped |
| h (tau3) | 21.62 | not routability-driven, density 0.70 | repair 312 303 buffers; detailed placement same picture -> stopped |
| u (tau6) | 21.62 | + `remove_buffers` (94 905 DC buffers) before gpl, SDC 2.0 ns (max transition 0.2), `gpl_incr.tcl` | repair 219 377 buffers, std-cell area **2.40 -> 5.21 mm2**: incremental gpl **GPL-0301 utilisation > 100 %** |
| **v (tau6)** | **23.97** | west strip 900, south band 400, north band 200 um; max transition **0.4 ns** (`QB_MAXTRAN`), density 0.62 | repair 121 384 + 68 123 buffers, std cells 4.64 mm2; detailed placement at 300-um limit **failed on 13 cells** (sequencer cluster, DPL-0036, 14 min); re-run at 1 000 um: **placed** (29.5 min step; avg / max displacement 18.9 / 1 583 um, HPWL +8 %) |
| w (tau3) | 23.97 | = v, timing-driven gpl | 16 min for 250 Nesterov iterations at overflow 0.90 (v: 0.58 at 400); stopped (no time) |

**Stop rule:** at 4.5 h (04:41 UTC) run v was in its second detailed placement; no global route existed for any run.
From then on only placement / CTS steps were run (no routing).

**Best placed result = run v [S]:**

| quantity | value |
|---|---|
| die | **4 040 x 5 933 um = 23.97 mm2** (placed, not routed) |
| blocks / ARM macros / top std cells / other | 9.703 (40.5 %) / 6.948 (29.0 %) / 4.642 (19.4 %) / 2.678 mm2 (11.2 %) |
| top std cells: DC -> placed | 2.511 mm2 (645 k cells, 94.9 k DC buffers removed) -> 4.642 mm2 (744 k cells; buffers / inverters 2.032 mm2, 249 k) |
| row area / cell utilisation in rows | 6.310 mm2 / 0.736 |
| vs the [E] 20.16 mm2 | +3.81 mm2 [R]: +2.13 mm2 top cells over DC (repair buffers / upsizing), the rest bands / halos / empty rows |

**Placement-based timing [OR est.]** (`impl/r5b/est_classes.tcl`, OpenROAD STA, placement parasitics, period
2.0 ns, block ETMs; `results/r5b/v_timing.txt`):

| class (worst endpoint) | pre-CTS (ideal clock, block clk latency -0.9) | post-CTS (TritonCTS, propagated) |
|---|---|---|
| top -> top flops | -7.714 ns (sequencer `pf_r` -> `RdB`) | -11.692 (B-map counter -> write address) |
| top -> block (excl. 3 ETM outliers) | -1.079 (`fv_p` -> col 7 `s_rd`) | -6.825 (prm `stg_t` -> col 1 `t2`) |
| block -> top | -4.186 (col 0 `w_vld_o` -> S write data) | -0.832 (same) |
| act chain to column 7 | -0.535 (`g_dist` -> col 7 `act[1664]`) | -4.118 |
| block-internal (R5d routed PT, [S]) | 489.6 / 299.1 MHz tt / ss | |

These are not the architecture's top-level fmax; they measure this placement [S]:
- **Unrepaired long nets after legalisation:** the worst paths have D0 / D1 cells driving 0.10-0.19 pF at 1.1-3.9 ns
  slew (e.g. `ND2D0` 0.19 pF, 2.08 ns; `AOI211D0` 3.90 ns).  The DRV repair ran before detailed placement, which
  then moved cells up to 1.58 mm.  A post-CTS DRV repair (`impl/r5b/cts_drv.tcl`) is section 4.1.
- **Clock tree:** TritonCTS over the 24-mm2 die: 3 796 clock nets, register latency 3.5-6.2 ns, **skew 2.68 ns**
  (`stg_t` 6.18 vs block clk 3.51 ns).  With `-insertion_delay` (the ETM clock-tree-path arcs) CTS found only 2
  clock nets (8 block clk pins + 40 793 registers, the gated subtrees not traced) and OpenROAD STA then found **no
  launch / capture path at all** (WNS reported 1e39): negative result, the run above is without it.
- **ETM outliers:** `pf[526]` is the worst top -> block endpoint (-4.70 / -8.56 ns) only through its 6.66-ns ETM
  setup arc (section 1).
- **Macro arcs:** the ARM image macro's CLK -> Q reads 999 ns in OpenROAD STA (`place_tt` WNS -998.9 ns; PT / DC
  read the same library correctly); `est_classes.tcl` starts its top classes at registers.

### 4.1 Post-CTS DRV repair (negative)

`impl/r5b/cts_drv.tcl` on `db/cts.odb` (1 thread; OpenROAD STA crashed with SIGSEGV in `Search::setVertexArrivals`
at 4 threads): **48 743** max-slew / cap / fanout violations on 19 070 nets after legalisation and CTS; repair
inserted 11 202 buffers and resized 11 164 cells (2 min).  The following detailed placement (200-um limit; it
re-legalises all ~0.8 M cells) was still in diamond search after 39 min and was stopped at 6.1 h for the write-up.
No timing number after this repair exists [S].

## 5. What failed and why (mechanisms) [S / R]

1. **Top-level buses x distance [S].**  The R4 architecture's top level is wide buses between the array, the weight
   / S / map / parameter macro banks and the host port (5 189-b `h_data` written into every memory bank).  At the
   die scale (4 x 6 mm), placement left 26-87 k nets longer than the repeater limit (RSZ "long wires") and
   1.27-1.45 M max-slew / max-fanout violations; at 0.2 ns max transition the repair alone took the top standard
   cells from 2.4 to 5.2 mm2.  This is the area the [E] estimate (logic x 1.47) did not have: it scaled DC logic by
   the column's P&R factor, which has no chip-scale wires.
2. **Legalisation of a 0.7-1 M-cell top level in OpenROAD [S].**  Detailed placement (single-threaded diamond
   search, stack sampled twice) took 14-40 min per attempt, failed once at 300 um, and when it succeeded (1 000 um)
   it displaced cells by up to 1.58 mm after the DRV repair, which is why the placed timing has 2-4-ns slews.  The
   R5c fix used for the column (FIRM templates + incremental gpl) exists for this flow only as `gpl_incr.tcl`; it
   ran, but did not remove the cluster overflow at the sequencer.
3. **DC topographical with black-box blocks [S].**  DC places its own die with the 8 blocks as 0.9-mm2 obstacles: it
   buffered the act chain between abutted blocks (CKBD12 per hop) and reported head / sequencer paths at -1.0 to
   -1.4 ns that run at 600-690 MHz in the whole-chip and standalone DC runs.  `remove_buffers` before gpl undoes the
   buffering (94 905 cells); a DC with a physical floorplan (DEF of the blocks / macros) would be the fix.
4. **Schedule [R].**  The stop rule hit while the fourth floorplan / recipe (v) was being legalised: t, h, u each cost
   30-60 min to reach the failure, DC 51 min, the first DC (wrong SDC: impl/constraints.sdc instead of
   impl/r4/constraints.sdc) 40 min.

**What would close it [R]:** (a) a floorplan that puts the act supply / sequencer / write-back logic in regions
sized for them (guides / fences; OpenROAD gpl here ignores regions, R5a) and the host port as a narrow serial /
banked bus instead of 5 189 b broadcast; (b) DRV repair after legalisation (4.1) and a clock tree built per region
(the column blocks' 0.9-ns insertion balanced explicitly); (c) a DC run with the physical floorplan.  Each is a
multi-hour step; none fits the remaining box.

## 6. Files, commands, disk

New `impl/r5b/`: `run.sh` (blk / syn / fp / pnr / pt), `gen.sh`, `core_blk.sv`, `dc_hook.tcl`, `lef_ring.py`,
`etm_ins.py`, `chip.cfg`, `mplace.py`, `dump_macros.tcl`, `pdn.tcl`, `pdn_macro.tcl`, `pre_place.tcl`,
`grt_probe.tcl` (not reached), `est_classes.tcl`, `cts_drv.tcl`, `area.tcl`, `pt_chip.tcl` (written for the routed
sign-off; not run: no route).  Changed, default-preserving: `impl/r4/run.sh` (`QB_EXTRA_DB_SS/TT/FF` appended to the
macro dbs, `QB_HOOK` replaces the DC hook; unset = as before).  No RTL / bench change (the cd-budget RTL option was
not needed, section 2).  Summaries: `results/r5b/` (`dc_top.txt`, `dc_top_violators.txt`, `runs_tuv.txt`,
`v_timing.txt`, `v_area.txt`).

```bash
# tau, from /tmp/ckp908/qc18bacc/repo, QC_BUILD=/tmp/ckp908/qc18bacc/build
qc18bacc/impl/r5b/run.sh blk r5d_B                 # block views -> $QC_BUILD/r5b_blk (tau3; copied to tau6)
qc18bacc/impl/r5b/run.sh syn                       # top DC -> syn/r5b_top (tau6, 51 min)
export QB_SYN=r5b_top QB_PNR_PERIOD=2.0 QB_WEST=900 QB_SB=400 QB_NB=200 QC_PNR_THREADS=15
qc18bacc/impl/r5b/run.sh fp r5b_v                  # init + macro dump + mplace.tcl
QC_PNR_TO=cts QB_RD=0 QB_DENS=0.62 QB_MAXTRAN=0.4 QB_POSTCTS=0 QB_DPL_ARGS="-max_displacement {1000 1000}" \
  QB_CTS_ARGS="-balance_levels -sink_clustering_buffer CKBD4" qc18bacc/impl/r5b/run.sh pnr r5b_v
# in pnr/r5b_v: QB_FROM=place|cts openroad est_classes.tcl ; cts_drv.tcl ; QB_DB=place openroad area.tcl
```

**Results on tau:** tau6 `pnr/r5b_v` (2.0 GB: init .. cts checkpoints, `cts_insdelay.odb` of the failed
insertion-delay CTS, reports), `syn/r5b_top` (DC netlist / ddc / reports), `r5b_blk` (block LEF exact + ring, ETMs +
`_ins` copies; also on tau3), `r5b_gen`; tau3 `syn/r5b_top` copy.  Deleted (own, superseded): tau6 `pnr/r5b_t`,
`pnr/r5b_u`, `syn/r5b_fake`; tau3 `pnr/r5b_h`, `pnr/r5b_w`, `syn/r5b_top_wlm`, `syn/r5b_fake*`, test runs
`r5b_fk*`.  `/tmp` free: tau6 65 GB, tau3 63 GB.
