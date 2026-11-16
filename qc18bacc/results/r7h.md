# R7h: full-chip DC topo netlist r7h_rp (QB_TOP_RSH=2 + QB_HEAD_PCOL=1), pre-route PT

[S] Same recipe, host, constraints and tools as `results/r7f.md`, env only: `QB_GEN=r7h_rp_gen QB_SYN_TAG=r7h_rp QB_DEFS_EXTRA="+define+QB_HPW=144+QB_TOP_RSH=2+QB_HEAD_PCOL=1"` (qb_top.sv at 2187974). Netlist on tau4: `build/syn/r7h_rp/qb_chip.v` (+ sdc spef ddc), 57 min.
`build/r5b_blk` on tau4 now also has `qb_col_blk_{tt,ss,ff}_ins.lib` and the exact `qb_col_blk.lef` (copied from tau6, md5 checked).

| | r6a_hpw144 | r7f_rp (RSH 1) | **r7h_rp (RSH 2)** |
|---|---|---|---|
| logic mm2 total / qb_top glue / act supply / head | 2.310 / 0.499 / 0.831 / 0.166 | 2.248 / 0.456 / 0.822 / 0.167 | 2.267 / 0.458 / 0.836 / 0.168 |
| PT fmax MHz tt / ss: act_supply class | 457.9 / 288.6 | 329.6 / 219.3 | **421.4 / 263.5** |
| worst endpoint into `u_act/sdq` (tt slack -> MHz) | -0.10 (S macro CLKA) -> 571 | -1.38 -> 330 | **-0.67 -> 431** |
| seq / prm / head (tt) | 409.4 / 471.8 / 331.2 | 421.0 / 461.8 / 300.1 | 426.2 / 468.9 / 302.7 |
| seq / prm / head (ss) | 261.1 / 298.4 / 212.3 | 266.1 / 292.5 / 197.2 | 269.9 / 296.8 / 194.3 |
| tokens tgo / deot tt; chip clock tt / ss | 476 / 558; 147 / 212 | 467 / 509; 173 / 197 | 477 / 527; 176 / 194 |

* **The select path is fixed, but act_supply is not back to 458 tt [S]** (`r7h/act_path_rp.txt`).
  (1) The act_supply class worst is now the act supply's internal ctx path `ival -> nav`, the same path as r6a's worst: -0.723 vs -0.534 ns. That gap is DC run-to-run variation (act supply 0.836 vs 0.831 mm2).
  (2) The worst `sdq` endpoints still start at a column block: `f_y[414]` (block output, 1.17 ns) -> HQ packing -> shared-rotator **data** input -> `sdq`, 2.06 ns, 431 MHz.
  With RSH=2 this path cannot carry data that sdq captures in an S-read data cycle, because the select is then on S. PT still times it, since the mux data input is timed regardless of the select.
  Removing it needs either an RTL change (stop f_y reaching the rotator data input combinationally, e.g. gate `rsh_xw` with a registered enable) or a justified false-path/multicycle constraint. PI to decide.
* DC: 2 x PROC-3 (helper process failed to connect), no other errors; 605 433 cells, 133 661 regs. Data: `r7h/dc_rp.txt`, `r7h/pt_rp.txt`.
