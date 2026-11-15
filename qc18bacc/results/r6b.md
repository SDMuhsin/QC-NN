# R6b: full-chip P&R of qb_chip with group-template top placement (run r6b_b)

Labels: **[S]** tool-reported (OpenROAD geometry / OpenROAD STA, tt, placement parasitics = **[OR est.]**);
**[R]** reasoning from [S] numbers; **[E]** estimate.  Host tau3, run dir `/tmp/ckp908/qc18bacc/build/pnr/r6b_b`
(`impl/r6b/run.sh pnr r6b_b`, QB_SPREAD 2, QB_SPREAD_ALL 1, QB_SNAP 1, QB_MAXTRAN 0.4, QB_DR_ITER 4, 15 threads).
Stop rules: GRT by 21:00 UTC Nov 15, nothing running at 23:20 UTC.

**Answer.**
- **Stage reached: CTS (db/cts.odb).  No global route, no detailed route, no DRC count, no SPEF / PrimeTime fmax.**
  The flow did not hit the stop rule; it **failed**: the post-CTS `repair_timing -setup` (impl/pnr/slice_post_cts.tcl,
  step route, 88 148 violating endpoints, WNS -10.778 ns) ran 19:01-19:41 UTC (inserted 2 642 buffers, resized 74 862,
  cloned 596, swapped 2 391), then `[ERROR RSZ-0025] max utilization reached` (P(MAX_UTIL) 90 %) and the flow exited
  (wall 50:37 from place, peak 8.2 GB) [S].  Nothing after db/cts.odb was saved.  Mechanism [R]: the rows were
  already 89.7 % full after CTS (std cells 3.679 mm2 in ~4.10 mm2 of rows [E]), so any upsizing of the 75 k resized
  cells exhausts the 0.3 % headroom.
- **Die 3 990.0 x 5 706.6 um = 22.769 mm2 [S]** (vs R5b placed 23.97).  Split at cts.odb [S]: column blocks 9.703
  (42.6 %), ARM macros 6.948 (30.5 %), top std cells 3.679 (16.2 %) = DC netlist cells 2.590 (623 795 inst, incl.
  repair_design resizing) + ICGs 0.026 (4 006 CKLNQD1) + repair buffers 0.849 (81 515) + CTS 0.213 (32 431);
  white space / halos / channels 2.439 (10.7 %).  No fill / tap / decap at this stage.
- **Timing at CTS [OR est.]**, 1.65 ns, tt: setup WNS -10.778 ns, TNS -140 240 ns, 88 148 endpoints; hold WNS -7.269,
  57 542 endpoints; i.e. ~80.5 MHz equivalent (1 / (1.65 + 10.778)) [R], not a sign-off fmax.  DRV at CTS:
  113.6 k max-slew, 14.9 k max-cap, 1.6 k max-fanout violators (limit 0.4 ns), worst slews 5-7.7 ns on repair-buffer
  (`wire*`, `max_length*`) inputs [S].
- **Top-5 critical paths [OR est.]** (`results/r6b/top5_cts.txt`): all `u_top/g_r3b_u_prm/stg_t_reg_*` -> column 3
  `t2[*]` (slack -10.78 .. -9.99).  Mechanism, worst path: launch clock latency **6.57 ns** (CTS cluster buffer
  `clkbuf_level_1_2_*` placed 1.6 mm west of its ICG, 1.27 ns slew at the ICG CP; ICG CKLNQD1 stage 1.64 ns into
  0.395 pF / 1.99 ns slew; subtree 1.73 ns) + data **5.22 ns**, of which 4.48 ns in two wire-buffer stages: the
  4-buffer chain detours flop (2 286, 1 566) -> (2 479, 337) -> (710, 3 280) -> (2 171, 4 702) -> block pin near
  (2 171, 4 692), ~8 mm of wire for a ~3.3 mm Manhattan distance [S locations, R length]; capture block clk 0.75 ns
  (ideal network delay) + setup 0.51.  So: clock latency/skew (~5.8 ns) + misplaced long-wire buffers (~4.5 ns);
  flop clk->Q + short buffers ~0.7 ns.  Clock skew report: 8.88 ns (stg_w_reg_2464_) vs 1.71 ns (col 3 clk), skew 7.17 ns [S].
- **Clock-gate finding [S].**  Post-CTS repair did **not** fix it: the setup repair aborted (RSZ-0025) without a
  checkpoint, and it does not size clock-network cells anyway [R].  At cts.odb, all **4 006 ICGs are CKLNQD1**
  (none upsized by CTS); output slew (tt): <= 0.15 ns 489, 0.15-0.3 806, 0.3-0.5 865, **0.5-1.0 1 071, > 1.0 775**
  -> **1 846 ICGs (46 %) above 0.5 ns**; worst 3.31 ns (`u_head/clk_gate_tacc_reg_43_`), then 14 `g_r3b_u_prm`
  stg_f / stg_w gates at 2.7-3.0 ns.  Cause: the ICG output net (ICG -> subtree root buffer) is long: HPWL
  <= 50 um 317, 50-200 923, 200-500 1 334, **500-1 000 985, > 1 000 um 447**, worst 2.9 mm; each ICG sits by its
  enable logic while its gated flops are spread by the group placement.  Fix options [R]: let CTS/repair size ICGs
  (CKLNQD4-16 in the buffer list / `repair_clock_inverters`-style pass), place ICGs at their sink centroid
  (clone ICGs per cluster), and raise MAX_UTIL or row area before a post-CTS repair.

## Files
- scripts: `impl/r6b/icg_probe.tcl` (ICG slews, named path, area split; QB_TOP5=1 -> 5 worst paths),
  `impl/r6b/icg_geom.tcl` (ICG output-net HPWL, cell locations), both read-only on a checkpoint.
- summaries: `results/r6b/r6b_b_state.txt` (flow stage lines + repair log), `icg_cts.txt`, `area_cts.txt`,
  `top5_cts.txt`.  Full reports stay on tau3 (`r6b_b/rpt/icg_cts.rpt`, `top5_cts.rpt`, `cts.drv.rpt`, `pc0_*.rpt`).
