# R9b: south hub hard block (r8d_rpg) -- partition, boundary, OpenROAD to GRT: **does not route, ~19 % gcells overflow**
[S] tool output, [R] reasoning; scripts `impl/r9b/` (run.sh dump|part|ports|sdc|equiv|fp|pnr|tcl), tables `results/r9b/`.
**Partition [S]:** cuts.py S group (all hub macros, prm, head, write-back / rotator / S-read glue) + rotator ends homed in qb_act2 +
pass table + head config + u_core south buffers (`part.py`); DC `group` -> qb_hub (0.841 mm2 std + 4.04 macros), broadcasts split
per column; pin-level structural equivalence (no usable Formality): 577 338 instances / 641 171 nets identical (`equiv.txt`).
**Boundary [S] (`boundary_bus.txt`, `pins_per_um.txt`):** 27 852 pins, all north: per column 2 640 straight under its south pins
(6.77 /um; pw / f_y / b2 / w_y registered, pf / s_rd / w_r comb from macro Q) + 137 M8 t2 / rst_n pins (over the array);
west strip 5 625 (act 2 652 comb, sequencer / glue 2 772, 6.73 /um).  Budgets from the column budgets (`sdc.py`).
**Placement [S] (H 1 700.6, 6.79 mm2; H 1 551.2 does not fit, util 0.92 after repair):**
- Root cause of the 924 DPL-0036 cells (run g0 dmap / `place_runs.txt`): DRV-repair buffers never re-spread after the 2nd repair
  (55 k um2 in channels / halos) and upsized S-pin glue packed in the 27-um S-row channels (all 64 left at y 1067-1082).
- Fix in `place_pre.tcl` (run g, TD): 40 % partial blockages on the 5 macro-row channels + incremental gpl after the last DRV
  repair -> legal with the default DPL window, std 1.76 mm2 (2.09x DC), place WNS -1.89 @ 1.85 ns.  CTS legalisation still
  left 13 cells -> {200 110}-um window (half an S macro).  Run f: TD off, 500-um window, std 1.79 mm2 after CTS.  `sdc.py`
  now sets EMA* = 0 / RETN = 1 case analysis (else STA takes the macros' uncharacterised EMA=100 arc: 999 ns).
**GRT [S] (3 congestion iterations, no post-CTS repair; `grt_f3.txt`, `grt_g2.txt`):** f 18.6 % / g 19.3 % of 3-um gcells
overflowed; overflow H 1.21 M / V 0.35 M tracks (g 2.09 M / 0.37 M).  By x: west strip 0 %, col0 16-23 %, col1-5 27-39 %,
col6 9-18 %, col7 0 %.  By y (f): band above the S rows 0.96 M H; S-row region 0.25 M H + 0.21 M V.  Guide demand vs nominal
tracks peaks on M3 / M5 (52-68 % under col2-4, before macro OBS) while M7-M9 stay at 13-27 %.  GRT WNS -3.7 (f) / -5.5 (g) ns.
**Not done (overflow far above 1 %):** DR, DRC, routed PT (peak RSS <= 6.0 GB); post-CTS repair (15 k endpoints) and a
50-iteration GRT each ran > 1 h unfinished, stopped.
**What-if [S] (`ovf9.py`: tracks of a class removed from each overflowed gcell, no rerouting) -- overflow left, f / g:**
| removed | share of tracks | overflow left |
|---|---|---|
| write-back (f_y regs -> rotators -> S / B write) | 37 / 38 % | 35 / 36 % |
| S-read -> act port (S / B Q + rotator) | 25 / 23 % | 41 / 45 % |
| params Q -> pf / pw | 14 / 13 % | 72 / 73 % |
| write-back + S-read / all three | 62 / 61 %; 76 / 73 % | 18 / 20 %; 0.4 / 1.2 % |
[R] The write-back rotator is the largest single lever and the S-read path the second; params alone is not enough, and no single
change routes: all three cross-column flows have to become column-local (or move to M7-M9 as wide buses) before the hub can route.
