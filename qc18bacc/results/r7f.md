# R7f: full-chip DC topo netlists with QB_TOP_RSH (r7f_rsh) and QB_TOP_RSH + QB_HEAD_PCOL (r7f_rp)

[S] DC W-2024.09-SP2 topographical, PT Q-2019.12-SP2, OpenROAD 2.0-12381.  Host tau4 (QC_CORES 6), build tree `/tmp/ckp908/qc18bacc/build`.
Recipe = `impl/r6a/syn.sh` (`impl/r5b/run.sh syn`, R4b + FW128 + 8 R5d block ETMs, 1.65 ns tt), env only:
`QB_GEN=r7f_gen QB_DEFS_EXTRA="+define+QB_HPW=144+QB_TOP_RSH=1" QB_SYN_TAG=r7f_rsh`; r7f_rp adds `+QB_HEAD_PCOL=1` (RTL 396183f).
Netlists: `syn/r7f_rsh/qb_chip.v`, `syn/r7f_rp/qb_chip.v` (+ .sdc .spef .ddc). r6a_hpw144 views copied from tau6 to `syn/r6a_ref` and re-timed on tau4.

| logic mm2 (`impl/r4/area_summary.py`) | r6a_hpw144 | r7f_rsh | r7f_rp |
|---|---|---|---|
| act supply / sequencer / qb_prm / head | 0.831 / 0.547 / 0.239 / 0.166 | 0.825 / 0.547 / 0.238 / 0.166 | 0.822 / 0.546 / 0.238 / 0.167 |
| qb_top glue / macro wrappers / qb_chip glue / u_core | 0.499 / 0.011 / 0.014 / 0.003 | **0.461** / 0.004 / 0.012 / 0.002 | **0.456** / 0.003 / 0.013 / 0.002 |
| **logic total** (macros 6.948 unchanged) | **2.310** | **2.255 (-0.055)** | **2.248 (-0.062)** |
| cells / regs | 623 589 / 133 660 | 608 315 / 133 661 | 607 437 / 133 661 |
| cuts.py --head-south S glue / S head / S std / W std | 0.348 / 0.166 / 0.753 / 1.511 | **0.290** / 0.167 / **0.695** / 1.513 | 0.290 / 0.167 / 0.695 / 1.509 |
PT pre-route (DC topo parasitics, 1.65 ns, `impl/r4/run.sh pt`, same SDC): fmax MHz tt / ss (`r7f/pt_*.txt`)
| class | r6a_hpw144 | r7f_rsh | r7f_rp |
|---|---|---|---|
| chip clock (act-chain ETM artefact tt; block -> head ss) | 147.2 / 212.3 | 169.4 / 190.4 | 172.8 / 197.2 |
| act_supply | 457.9 / 288.6 | **333.3 / 221.5** | **329.6 / 219.3** |
| seq / prm | 409.4 / 471.8 ; 261.1 / 298.4 | 441.9 / 471.9 ; 281.1 / 300.8 | 421.0 / 461.8 ; 266.1 / 292.5 |
| head (block clk -> pool) | 331.2 / 212.3 | 296.8 / 190.4 | 300.1 / 197.2 |
| tokens tgo / deot (tt) | 476.1 / 557.6 | 450.9 / 505.8 | 466.7 / 508.8 |

* **New act_supply critical path from RSH [S]** (`r7f/act_path_rsh.txt`): column `f_vld_o` (block output, 1.07 ns) -> `rsh_hq = fo.v && f_vld_o && fo.hm`
  -> select of the shared 2048-b rotator (input mux + shift) -> `s_q` -> `u_act/sdq_reg` (2 048 endpoints, -1.35 ns tt). The S-read path now waits
  on a block output. Fix: drive the rotator select from a register (e.g. the S-read data-cycle flag `s_ren` delayed 1, S priority; exclusivity is already checked by `rsh_err`).
* Naming compatible with `impl/r6a/cuts.py`. Each netlist was linked unplaced in OpenROAD (`nl_dump.tcl`, net_dump format), and cuts.py ran without changes, with no `glue?` cells.
  Instance counts match DC exactly. PCOL slices stay as hierarchy `u_head/g_pcol_<c>__u_pc` (16 397 of 40 167 head cells), labelled S/head, not per column.
* DC log: 2 x PROC-3 (a multicore child process could not connect, "Network is unreachable"); the step went on without it. No other errors. RSH +1 register vs r6a.
* For P&R on tau4: `r5b_blk` has only the ring LEF + ETM .db files. The `*_ins.lib` P&R copies (impl/r5b `blk` step) are still on tau6 only. ARM macros were copied to `/tmp/ckp908/qcnn/macros`.
