# R7e: shared write-back / S-read rotators (opt-in RTL `QB_TOP_RSH`, default 0 = R7d RTL)

**[M]** RTL sim, **[S]** Yosys, **[D]** DC; data `results/r7e/{tb,yosys,dc}.txt`.  **Result: exact, -28 % rotator logic [M+D].**  10 val images bit- and cycle-identical; S-read mutant and checker test caught;
wrapper DC -22.5 k um2 comb (-28 %), -11.3 k cells, -11.3 k nets, almost all from (a).

## 1. RTL (`hw/rtl/qb_top.sv`, under `QB_TOP_RSH`; meaningful with `QB_TOP_WBR = QB_TOP_SROT = 1`)
* **(a) `g_rsh`:** one 2048-b 16-lane log rotator; input `rsh_hq ? rsh_xw : (s_grp_q ? s_mq[16..31] : s_mq[0..15])`, shift
  `rsh_hq ? 16 - l0 : s_rot_q` (up by l0 = down by 16 - l0); `rsh_hq = fo.v && f_vld_o && fo.hm`, `rsh_xw` / `rsh_l0` =
  unrotated HQ packing (own always_comb).  Output -> `s_q` (replaces `g_srot`) and HQ words `xw`.  HQ 8-b address rotator
  stays separate (S read has none).  No added registers.
* **(b)** HQD + Z on one 16 x 64-b payload + 8-b address rotator (`rup16p`, `rup8`), Z priority: payload = `xd[63:0]`
  (HQD) / `xz[8b]` in bits 0..15 (Z); `df[16+l] = {p, p}`, `dw[16+l][32q+8cc+i] = p[4q+cc]`.  Z writes set `ew[16..31]`,
  so HQD `df` there is unused: identical to the old `ew ? dw : df` for all inputs.
* **Check (sim only, `ifndef SYNTHESIS`):** `rsh_err` (ORed into chip `err`) if `s_ren` delayed 1 (S-read data cycle) &&
  `rsh_hq`.  Mutants: `QBT_MUT_RSH` (S read uses the HQ shift), `QBT_MUT_RSHC` (check window at distance 11 either order).
* Yosys-slang elaboration of `qb_top` (SYNTHESIS + R4b defines, RSH 0 / 1): OK, identical warning sets.

## 2. Verification [M] (Verilator 5.050, QBT_TECH=2 + QB_HEAD_FW=128 + QB_HPW=144; R7d vectors)
| build | s0 val 60 61 0 1 2 | s1 val 13 55 7 42 91 |
|---|---|---|
| RSH=1 | PASS (100/100 logits, 600/600 tiles cycle-exact, err 0); `--check` torch.equal 5/5 | PASS; 5/5 |
| RSH off | (R7d) | PASS; torch.equal 5/5 |
| `QBT_MUT_RSH` | FAIL: 15 tile-cycle mismatches, torch.equal 0/5 | FAIL, 0/5 |
| `QBT_MUT_RSHC` | err 1 FAIL (checker sees both signals aligned) | err 1 FAIL |
RSH=1 s1 bench output == RSH-off build, line for line; s0 == R7d `sim_chip_st.log` (minus stats).  Plain default builds.

## 3. Area [S, D] (`impl/r7e/wbs.sv`: 4 rotators + lane 16..31 output mux; DC tt 1.65 ns, registered shell, all met)
| variant | Yosys cells / nets | DC comb um2 | DC comb cells | DC nets |
|---|---|---|---|---|
| old | 24 612 / 18 392 | 79 609 | 37 493 | 43 903 |
| new (a+b) | 20 322 / 16 150 | **57 074 (-28.3 %)** | 26 183 | 32 595 |
| (a) only | 18 485 / 14 313 | 58 000 | 26 361 | 32 773 |
| (b) only | 26 431 / 20 211 | 78 697 | 37 351 | 43 761 |
(b) adds only -926 um2 in DC on top of (a).  Yosys reports (b) as +1 819 cells, but that is an artefact: it turns the lane 16..31 mux into
AND/OR logic when the payload select and the mux select are the same signal (`wbz.sv`).  With an independent select, the
cost is 5 516 vs 6 088 cells.  Scale: -0.023 mm2 of a 23.2 mm2 die; the real gain is fewer south-band nets (R7a).
## 4. Files / commands
`impl/r7e/`: `wbs.sv`, `wbs_top.sv`, `wbz.sv`, `dc.sh` (tau4: `QC_BUILD=/tmp/ckp908/qc18bacc/build qc18bacc/impl/r7e/dc.sh
old|new|a|b` -> `build/syn/r7e_wbs_*`).  Yosys: `impl/r7d/syn.sh impl/r7e/wbs.sv new RSH`.  Bench: `QBT_TECH=2
QBT_DEFS="+define+QB_HEAD_FW=128+QB_HPW=144+QB_TOP_RSH=1" hw/tb/run_tb_chip.sh build`, run / `--check` as r6a.md section 5.
