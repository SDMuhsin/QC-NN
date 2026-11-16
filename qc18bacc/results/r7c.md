# R7c: act supply (qb_act2) as a standalone hard block for the west strip (tau4) -- negative: not routable at <= 820 um
**[S]** DC / OpenROAD / PT numbers ([OR est.] = OpenROAD estimate); **[E]** estimate.  Host tau4 (fresh: OpenROAD installed,
repo rsync'd, column ring LEF copied from tau3 via NFS), build `/tmp/ckp908/qc18bacc/build`.  Flows `impl/r7c/` (`run.sh`
syn | pins | pnr | post | abs | abs0), tables `results/r7c/*.txt`.  Default builds unchanged.

**Answer.**
- **[S] Block `qb_act2_blk` = qb_act2 #(ACT_PIPE 2) = u_act + the g_dist 4 608-b register.**
  - The act pins come straight from the last flop, so the block abuts column 0 with no top register.
  - Act timing is unchanged (act at i + 3 + AP + DIST).  Integration: qb_top AP 2 / DIST 0 (D stays 4).  Only the
    unused debug a_* outputs shift by one cycle.
- **[S] DC topographical, 1.65 ns tt: 910 476 um2, 56 857 regs.**
  - Split: comb 488 613 (of which buf / inv 118 611), seq 421 863.  Line buffers 2 x 225 k, S1 237 k, S2 84 k, act
    pipe 73 k.
  - Pre-route PT **601.9 / 384.9 MHz tt / ss**.  The critical path is ctx 0 `ival_reg -> nav_reg` (issue sequencer).
  - DC leaves 60 083 max-transition nets and 12 629 max-fanout nets (`dc.txt`).
- **Goal not met: no routed block, so no DRC count, no SPEF fmax, no routed abstracts.**  14 attempts: `runs.txt`,
  `postcts.txt`.
- **[S, OR est.] Routability (`grt_b4.txt`).**  B4: 820 x 2 420, util 0.654 after CTS and repair.  GRT with
  -allow_congestion: **demand 115 % of capacity; vertical 151 % (M2 182 %), horizontal 76 %**; wirelength 55.7 m.
  - Overflow sources: line buffer 22-30 %, S1 17-20 %, S2 11-16 %, repair buffers 14-18 %; sdq / rdq < 0.5 %.
  - So the limit is the gather crossbar inside the block (as R7a's 157 % V), not the S / map input pins.
  - [E] At <= 85 % usage this placement needs >= 2.65 mm2 = 820 x ~3 240 um, more than the 3 110-um array height.
- **[S] Area mechanism: the DRV repair grows with the die.**
  - Column constraints (0.2 ns max_tran, max_fo 16): +43 / +60 / +75 % cell area at H 1 910 / 2 420 / 3 110; after
    the second pass, util 0.97 / 0.85 / 0.75.  Taller dies stretch the gather nets (south S pins to east act rows).
  - Opt-in `QB7_MAXTRAN 0.40` / `QB7_MAXFO 64`: +23 / +27 / +41 %.  Die / DC is then 1.72 at H 1 910 (util 0.73,
    0.82 after CTS + repair) and 2.18 at H 2 420; the column block is 1.566.
- **[S] Legalisation mechanism.**
  - Default DPL fails (DPL-0036) on 94-398 clumped cells: the 2 865 top-level act port BUFFD2s and pipe-1 flops at the
    east edge, plus S1 / S2 / line-buffer cells.
  - A 500-um window places them, but the moves destroy the repaired timing.  B4: -0.335 after setup repair, -0.786
    after its legalisation, -3.202 after hold legalisation, -4.14 ns at GRT.  {100 100} fails again after CTS (B5).
- **[S] Constraint bug, found late.**  `QB_IO_LAT` 0.85 (the column value) vs the act-pipe clock latency 0.55 ns.
  - Every act output gets an artificial ~0.2-ns hold violation.  The hold repair then builds BUFFD1 chains: B4 worst
    `g_pipe_1 q_reg -> act[2313]`, 9 stages at 0.11-0.17 pF.
  - Use `QB_IO_LAT=0.55`; B5 had it but stopped at the CTS legalisation.
- **[S] Abstracts on tau `$B/r7c_blk` are pre-route stand-ins.**
  - `qb_act2_blk.lef` + `_ring.lef`: B4 floorplan, 7 376 pins, M7 PG straps.  LEF SIZE says y 2 413.965 vs die 2 420:
    fix before use.
  - **Act abutment with column 0's LEF: 4 608 / 4 608 pins match** (layer, shape, y with yoff 690, east edge).
  - ETMs `qb_act2_blk_pre_{tt,ss,ff}`: DC netlist + DC SPEF, ideal 0.55-ns latency.
- **Runtime:** DC 25 min; P&R place 25-32 min; CTS + post-CTS repair 35-60 min (DPL diamond search); GRT probe 21 min.
  Peak RSS 9.2 GB.

**[E] Not done, would close it:** (1) structured placement as R5c (act pipe in east act-row bands, S2 beside, S1 interleaved
with its line-buffer slots, sdq / rdq south); (2) DC with DRV fixed at the P&R period; (3) `QB_IO_LAT` 0.55, DPL window in
place only, `QB_RT_LOOPS` >= 1; or (4) one block per context, to halve the gather fan-in.
Repro: `run.sh syn; run.sh pins; QC_PNR_THREADS=5 QB_W=810 QB_H=2410 QB_DENS=0.80 QB7_MAXTRAN=0.40 QB7_MAXFO=64 QB7_DPL_ARGS=
"-max_displacement {500 500}" run.sh pnr r7c_B4` (A4 H 1900, C4 3100); `run.sh abs0 r7c_B4 pdn`; `grt_probe.tcl` (QB7_RUN).
