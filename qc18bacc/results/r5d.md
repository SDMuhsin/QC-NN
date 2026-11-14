# R5d: decode before the code register (qb_core CREG 2) + wide-lane shift precompute, column block `qb_col_blk`

Labels as `results/r5c.md`: **[S]** static (DC / PrimeTime with the def2spef SPEF, or OpenROAD's own estimate where
marked [OR est.]); **[M]** simulation; **[R]** reasoning from [S] / [M] numbers.  Tools as R5a / R5c.  Host tau3 (variants T / C on tau6),
build tree `/tmp/ckp908/qc18bacc/build`.  Reference = R5c run B (`pnr/r5c_B`: 462.1 / 289.5 MHz tt / ss).

**Answer.**
- **Goal not met: routed PT reg2reg 489.6 / 299.1 MHz tt / ss [S]** (run B 462.1 / 289.5: **+6.0 % / +3.3 %**).
  Zero cycle change and bit-exact: core bench E6_s1 val 7 / 123 0 errors at the same cycle counts, 3 mutants
  caught [M]; 8-copy gate level of the repaired netlist, img0 / img1 (s0) + img7 / img123 (s1), 0 errors [M].
- **Both targeted limiters are gone at tt.**  dec -> BR had 28 endpoints at -0.164 and now has 0.  Wide lane
  `sh1 -> y2` had 5 at -0.126 and now has 0 (the wide lane's worst is now S1 `x0 -> p1` at -0.013).
- **New tt limiter: PE row 0-3 shadow -> fused-lane input** `u_shd/shd_reg -> u_lf/u_rin`.  32 endpoints, worst
  -0.043 ns.  The path is 1.19 ns logic + 0.30 ns repeaters + 0.27 ns wire, 0.25 pF, about 1 mm from PE row 2 down
  into the lane band.  It was run B's third class (1 endpoint, -0.011).  **ss limiter:** BR g7 -> PE row 14
  popcount.
- **Cost of CREG 2: the north input budget [S].**  north2reg is now -0.083 ns at tt (run B +0.575): the 1.16-ns
  decode + NNw now sits inside the block's 0.30 P `cd` budget.  This is an IO-contract item, not reg2reg (section 4).
- **DC (1.65 ns, same flow): 745 202 um2, -29 372 (-3.8 %) vs 774 574; regs +82 (25 905) [S].**  Pre-route PT is
  592.5 / 379.7 MHz tt / ss (601.8 / 387.5).  DC's worst path is now the north input `cd -> nw_reg` (-0.031).
- **P&R (run B recipe):** DR **8 178 markers** after the same 7 iterations (B 10 830).  Final cell area 873 555 um2
  (B 888 388).  Same die and pins.
- **Variants on tau6 [S]:**
  - T (decoder band at the top): no better at GRT, stopped.
  - C (same netlist, P&R SDC 1.9 ns): routed **485.6 / 283.9 MHz**.  The lane classes close, but BR -> popcount
    gets worse; DR 14 310 markers.  Negative result.
- **What is left for 500 MHz (~45 ps):** a lane-band floorplan item.  The fused-lane S0 should sit next to PE rows
  0-3.  This is section 4.

## 1. Step 1: where run B's violators are (PT, routed, SPEF)

`impl/r5d/hist.sh r5c_B <corner> <P>` re-runs `impl/r5a/pt_blk.tcl` (same netlist, SPEF, IO budget shifted by L) in a
scratch dir and dumps every setup-violating endpoint (one worst path each) with the path split into logic cells,
repeater cells (BUFF / CKBD / INV / CKND / DEL) and net (wire) delay, and the max net C on the path;
`impl/r5d/hist.py` groups them by instance-name prefix.  Raw dumps: `results/r5d/viol_B_*.txt`, tables
`results/r5d/hist_B.md` [S].

**tt, P = 2.0 ns (417 endpoints by `report_constraint`, 418 paths):**

| class | endpoints | worst slack ns | worst path | cells (repeaters) | logic / rep / wire ns | max net C pF |
|---|---|---|---|---|---|---|
| act feedthrough act -> act_o (IO budget 0.07 P) | 344 | -0.029 | `act[1891] -> act_o[1891]` | 2 (1) | 0.00 / 0.05 / 0.04 | 0.039 |
| `s_rd` -> fused lane `u_rin` (IO, south 0.20 P) | 40 | -0.101 | `s_rd[102]` -> `g_fq_0__g_fc_0__g_fi_6__u_lf/u_rin/q_reg_43_` | 24 (4) | 1.18 / 0.14 / 0.07 | 0.112 |
| **dec -> BR `nnw_q`** (reg2reg) | **28** | **-0.164** | `cdr_reg_79_` -> `g_grp_1__u_br/nnw_q_reg_8_` | 24 (5) | 1.48 / 0.27 / 0.15 | 0.173 |
| **wide lane S1 -> S2** `sh1 -> y2` (reg2reg) | **5** | **-0.126** | `g_wq_0__g_wc_0__u_lw/sh1_reg_1_ -> y2_reg_0_` | 31 (6) | 1.35 / 0.39 / 0.11 | 0.197 |
| PE shadow -> fused `u_rin` (reg2reg) | 1 | -0.011 | `g_r_1__u_pe/u_shd/shd_reg_45_ -> g_fq_1__..._fi_2__u_lf/u_rin` | 25 (5) | 1.29 / 0.16 / 0.25 | 0.255 |

Only 34 of the 417 are reg2reg; 384 are IO-budget classes.  No PE, BR -> PE or PE-internal endpoint violates at tt.

**ss, P = 3.0 ns (1 461 endpoints; top groups):**

| class | endpoints | worst slack ns | worst path | logic / rep / wire ns | max C pF |
|---|---|---|---|---|---|
| act feedthrough (IO) | 1 245 | -0.064 | `act[1891] -> act_o[1891]` | 0.00 / 0.10 / 0.04 | 0.043 |
| `s_rd` -> fused `u_rin` (IO) | 77 | -0.377 | `s_rd[102]` -> fused lane 6 `u_rin` | 2.05 / 0.27 / 0.07 | 0.133 |
| dec -> BR `nnw_q` | 52 | -0.454 | `cdr_reg_79_ -> g_grp_1__u_br/nnw_q_reg_8_` | 2.54 / 0.47 / 0.16 | 0.205 |
| wide lane `sh1 -> y2` | 49 | -0.454 | `sh1_reg_1_ -> y2_reg_18_` | 2.50 / 0.59 / 0.01 | 0.056 |
| BR -> PE popcount S1 | 17 | -0.361 | `g_grp_7__u_br/c_q_reg_228_ -> g_r_14__u_pe/.../u_q_reg_153_` | 2.44 / 0.65 / 0.02 | 0.094 |
| PE S1 -> S2 acc | 14 | -0.080 | `g_r_2__u_pe/ctl_p_reg_3_ -> acc_reg_158_` | 2.30 / 0.54 / 0.01 | 0.058 |
| fused lane stages | 9 | -0.111 | `u_rlate -> g_fin2_u_rmid` | 2.25 / 0.53 / 0.02 | 0.077 |

Reading [R]: both reg2reg limiters are **logic-dominated** (wire 0.11-0.15 ns of 1.9 ns), with repeater / high-C
nets on top: dec -> BR = 8-b -> 10-b decode + the 36-input NNw count (10-b adder tree) + the fan-out to 8 BRs over
the column (0.17-pF repair nets); wide lane = `sh1 - 1` (a 6-b decrement: NR2 -> BUFFD4 -> CKXOR2 at 0.48-ns slew
in the ss report) feeding the select of the 51-b barrel shifter, then round / saturate.  So step 2 targets these two
(PI's decode-before-register, plus the decrement precompute), both cycle-neutral.  The IO classes are budget
contracts, not reg2reg (section 4).

## 2. Step 2: RTL (cycle-neutral, bit-exact)

- **`qb_core` CREG 2** (new value; 0 / 1 unchanged): the 36 decoders + NNw of a column (`qbc_coldec`) sit on the
  port side (`cd`, `ctl[6:7]` at cycle n-1), and a register `g_col_*.dc / nw` (360 + 10 b per column) replaces
  `cdr` (288 b); `ctlr` stays.  Register -> BR is wire only.  Same edges as CREG 1 (port n-1 -> register n -> BR
  n+1 -> S1 n+2), so b2 latency, `ND`, and every port timing are unchanged.  In qb_top the `cd` port is driven by
  `cdp[D-4]` (a `qbt_dreg` pipeline register), so the decode lands on top-flop -> block-flop, inside the north
  input budget (0.30 P).  The PE gets CR = 1 for any CREG != 0 (PE logic and module names unchanged).
- **`qbcw_lane` SHP 1 / `qb_core` WSHP 1** (new, default 0): S1 registers `sh0 - 1` instead of `sh0`; S2 shifts by
  `sh1` (same 6-b wrap-around value, same y2).
- **`qb_col_blk`**: defines `QB_COL_CREG` (default 1) / `QB_COL_WSHP` (default 0); `impl/r5d/qb_blk_r5d.f` = `qb_blk.f`
  + both.  `tb_qb_core.sv`: `QBC_WSHP` (default 0).  Default builds elaborate exactly as before.
- **P&R classifier** `impl/pnr/slice_bands.tcl` `qb_class`: the CREG-2 decoders / register (`g_col_0__g_dreg_u_dec/`,
  `g_col_0__(dc|nw)_reg`) are class `dec` (seeded where run B seeded the decoders + `cdr`); additive regex, no
  existing netlist has these names.

**Verification [M]** (`hw/tb/run_tb_core.sh`, Verilator, E6_s1 val 7 / 123 vectors of `export_core.py`, GPU 0;
`results/r5d/tb_core.txt`):

| build (QBC_DEFS = CREG 1 / WTP / FTP / PPOP / BRG 2 baseline, or CREG 2 + WSHP 1) | img7 (3 628 cycles) | img123 (3 676 cycles) |
|---|---|---|
| baseline CREG 1 | PASS 630 784 words, 0 err | PASS, 0 err |
| **new CREG 2 + WSHP 1** | **PASS, 0 err, same cycles** | **PASS, 0 err, same cycles** |
| new + `QBC_MUT_DEC` | caught (201 905 err) | caught (204 062) |
| new + `QBC_MUT_NNW` | caught (65 536) | caught (65 536) |
| new + `QBC_MUT_G3N` | caught (65 536) | caught (65 536) |

**Gate level [M]** (`impl/r5a/gls.sh r5d_B`, 8 abutted copies of the routed run's netlist after DRV repair, CTS
and the post-CTS setup / hold repair (`write_verilog` of `db/cts_rt.odb`, as R5c), VCS zero-delay;
`results/r5d/gls_r5dB.txt`):

| vectors | cycles | words | errors |
|---|---|---|---|
| s0 val 0 (`r5a_vec/img0`) | 3 644 | 630 784 | **0** |
| s0 val 1 | 3 684 | 630 784 | **0** |
| E6_s1 val 7 | 3 628 | 630 784 | **0** |
| E6_s1 val 123 | 3 676 | 630 784 | **0** |

The cycle counts equal R5c run B (img0 / img1 3 644 / 3 684) and the RTL bench (img7 / img123 3 628 / 3 676).

## 3. Results: DC, P&R, PT

DC: `impl/run.sh all qb_col_blk 1.65` with `QB_FL=impl/r5d/qb_blk_r5d.f`, same hook (`impl/r5a/topo_col.tcl`), same
compile, tag `qb_col_blk_r5d_s20_tt_p1.65_topo`.  P&R: `impl/r5d/run.sh` = the R5c run-B recipe on this netlist
(16 new PE templates, 376 um / density 0.70, tiled FIRM; `impl/r5a/col.cfg` knobs; P&R period 2.0; DR
`QB_DR_ITER 6`).  PT: `impl/r5a/post.sh pt` (period 2.0, IO budget shifted by L).

| quantity | R5c run B | **R5d run B (`r5d_B`)** | label |
|---|---|---|---|
| DC cell area / regs | 774 574 um2 / 25 823 | **745 202 um2 (-3.8 %) / 25 905 (+82)** | [S] |
| DC WNS at 1.65 / worst | 0.000 / PE shd -> wide lane | -0.031 / **`cd[53] -> nw_reg_6_` (north IO)** | [S] |
| DC netlist, pre-route PT tt / ss | 601.8 / 387.5 MHz | 592.5 / 379.7 MHz | [S] |
| PE templates: max y10-90 | 86 um | 85 um | [S] |
| place WNS (all) | -0.156 (dec / BR) | -0.216 (`cd -> nw_reg`, north IO) | [S, OR est.] |
| post-CTS: pre-repair / repaired / legalised + hold | -0.346 / -0.020 / -0.076 | -0.183 / -0.035 / **-0.039** | [S, OR est.] |
| post-GRT r2r (classes) | -0.160 (dec_br -0.16, lane_w -0.16, lane_f -0.06) | **-0.083 (lane_f -0.08, lane_w -0.05)** | [S, OR est.] |
| DR markers it 0-6 | 340 901 / 171 817 / 160 214 / 64 263 / 31 771 / 17 458 / **10 830** | 332 529 / 171 175 / 159 947 / 64 226 / 30 965 / 14 779 / **8 178** | [S] |
| DR classes (final) | M2 short 5 690, M3 short 1 730, VIA1 cut 998 | M2 short 4 187, M3 short 1 249, VIA1 cut 897, M2 spacing 724; 6 643 of 8 178 at x 150-225 um (same stripe), y 1 550-2 300 | [S] |
| cell area end / utilisation | 888 388 / 0.754 | 873 555 / 0.742 | [S] |
| **PT reg2reg fmax tt / ss** | 462.1 / 289.5 MHz | **489.6 / 299.1 MHz** | [S] |
| crit tt | `cdr_reg_79_ -> u_dec -> BR g1 nnw_q_reg_8_` | `g_r_2 u_shd/shd_reg_60_ -> g_fq_2..fi_3 u_lf/u_rin/q_reg_43_` (0.25 pF, 27 cells) | [S] |
| crit ss | wide lane `sh1 -> y2` | `BR g7 c_q_reg_333_ -> PE row 14 popcount u_q_reg_8_` | [S] |
| IO tt: north2reg / south2reg / act feedthrough | +0.575 / -0.101 / 0.169 ns (budget 0.140) | **-0.083** / -0.126 / 0.156 ns | [S] |
| hold reg2reg tt / ss (violating endpoints) | -0.002 / +0.010 (1) | -0.011 / -0.002 (4, `u_pbf late -> u_rlate`) | [S] |
| clock insertion L tt / ss | 0.93 / 1.41 | 0.90 / 1.36 | [S] |
| P&R wall | 2:22 | 2:13 (+ 16 templates ~11 min) | [S] |

**Violating endpoints after the fix (`results/r5d/hist_r5dB.md`) [S]:**

| class | tt P 2.0: endpoints / worst | ss P 3.0: endpoints / worst |
|---|---|---|
| act feedthrough (IO) | 283 / -0.016 | 839 / -0.045 |
| `s_rd` -> fused `u_rin` (IO) | 238 / -0.080 | 386 / -0.317 |
| **PE shadow -> fused `u_rin`** | **32 / -0.043** | 16 / -0.102 |
| wide lane (now S1 `x0 -> p1`) | 11 / -0.013 | 84 / -0.300 |
| south in -> other (IO, `s_rd -> u_rlate`) | 10 / -0.126 | 19 / -0.334 |
| north in `cd -> nw_reg` (IO, new) | 4 / -0.083 | 8 / -0.302 |
| BR -> PE popcount | 1 / -0.008 | 58 / -0.344 |
| PE S1 -> S2 acc | 0 | 150 / -0.163 |
| fused lane stages | 0 | 32 / -0.137 |
| **dec -> BR** | **0** (B 28 / -0.164) | **0** (B 52 / -0.454) |
| total | 579 (reg2reg 44) | 1 592 |

## 4. Mechanisms and what is left

- **dec -> BR fixed, as intended [S].**  The register -> BR path is now wire plus repeaters to the 8 BRs; no endpoint
  of that class violates at tt or ss.  The decode + NNw count (1.16 ns of logic at tt, routed) moved onto `cd` pin ->
  `nw_reg`.  That is an IO path: north2reg goes from +0.575 to -0.083 ns at the 0.30 P budget.
  - The top-level side of that path is qb_top's `cdp[D-4]` register -> wire to the column top [R].
  - A cycle-neutral way to close it: decode one stage earlier inside qb_top's `cdp` pipeline, so the block port
    carries the 370-b decoded word per column (+82 north pins, +82 x 8 flops in qb_top) and the block registers it
    directly [R].  The other way is to renegotiate the north budget down to about 0.25 P.  Neither was done here.
- **Wide lane fixed [S].**  In run B, `sh1 - 1` was a decrement (CKXOR2 at 0.48-ns slew) in the select of the 51-b
  barrel shifter.  Precomputing it removes `sh1 -> y2` from the violators.  The lane's worst is now its S1 multiplier
  `x0 -> p1`: -0.013 tt, logic 1.68 ns.
- **New limiter: PE shadow (rows 0-3) -> fused lane `u_rin` [S].**  Measured from `cts_rt.odb` [S]:
  - The fused lanes sit at y 12-977 um (mean ~520 um), all four row groups mixed.
  - The rows 0-3 shadow registers sit at y 1 237-1 606 um.
  - So each drain bit crosses ~0.7-1.4 mm.  It then goes through the `fs_q` mux (MUX2D0 in this netlist) and the
    lane pre-processing (`qbf_pre`: sign, 22-b bias add, ReLU) before `u_rin`.
  - It cannot be pipelined without +1 lane latency (u_rin is the lane's S0).  The PE side is out of scope.  So it
    is a floorplan item [R]: the fused-lane inputs / `qbf_pre` belong at the top of the lane band, next to PE rows
    0-3, with the parameter banks at the bottom.
  - DC also sized this netlist 3.8 % smaller, lanes -5 % [S].  DC's worst path was now the north IO `cd -> nw_reg`,
    so the lanes got less upsizing headroom than in R5a.  That is consistent with lane_f worsening from -0.06 to
    -0.08 at GRT [R, not isolated].
- **Variants, partial [S, OR est.]:**
  - **T** (tau6, `QB_DEC_TOP 1`: a 47-um decoder band at the top, by the `cd` pins): post-CTS legalised -0.008,
    post-GRT r2r -0.098 (lane_f -0.10, lane_w -0.05).  No better than B at GRT, so I stopped it before DR (log
    `results/r5d/summary_r5dT_partial.txt`).
  - **C** (tau6, P&R SDC period 1.9 ns, same netlist / tiles): post-GRT r2r -0.167 at 1.9, i.e. 1 / 2.067 =
    484 MHz.  B at GRT was 1 / 2.083 = 480 MHz, so over-constraining looked worth ~1 % at GRT.
    **Routed it is worse [S]:** PT 485.6 / 283.9 MHz tt / ss (B 489.6 / 299.1), crit `BR g6 c_q -> PE row 13
    popcount`, DR 14 310 markers after 7 iterations (B 8 178), cell area 890 121 um2 (B 873 555).  Its tt
    violators (`hist_r5dC.md`, 161) show the trade [S]:
    - PE shadow -> fused `u_rin` and the wide lane drop to **0** endpoints (B: 32 and 11).
    - BR -> PE popcount (10, -0.059) and the `fs_q` select -> `u_rin` fan-out (8, -0.053, 0.17 pF) take over.
    - Mechanism [R]: repair at 1.9 ns adds 16.6k um2 of buffers / upsizing, which raises routing demand in the PE /
      BR rows (+75 % DR markers), so the routed BR broadcast nets get slower.
    - Negative result for the whole column, but it shows that the lane class closes with ~0.1 ns more repair
      effort (`results/r5d/pt_blk_r5dC_*.txt`, `summary_r5dC.txt`).  Run C's netlist also passes the 4-image 8-copy GLS, 0 errors (`gls_r5dC.txt`) [M].
- **To reach 500 MHz tt [R]:** about 45 ps on 32 + 11 + 1 reg2reg endpoints.  The candidates are lane-band
  floorplanning (fused-lane S0 near PE rows 0-3) or a lane-latency change, which is not cycle-neutral.  Both are
  outside this task's rules.  The `s_rd` IO class (238 endpoints, -0.080 / -0.126 at the 0.20 P south budget) is
  unchanged in kind.  qb_top already registers `rq_r` and then muxes by `f_pg3` before the block.  Moving that mux in
  front of `rq_r` would be cycle-neutral on the top side and would justify a tighter south budget [R, not done].
- DR stripe: the markers stay at x 150-225 um, as in R5c run B (popcount / BR-broadcast crossbar of the templates).
  Not addressed.

## 5. Files, commands, disk

New: `impl/r5d/` `hist.tcl`, `hist.sh`, `hist.py` (violator dump / grouping), `qb_blk_r5d.f`, `run.sh` (templates ->
P&R -> SPEF / PT / hist / DR histogram -> GLS).  Changed, default-preserving: `hw/rtl/qb_core.sv` (CREG 2, WSHP,
`qbcw_lane` SHP), `hw/rtl/qb_col_blk.sv` (`QB_COL_CREG` / `QB_COL_WSHP` defines, defaults 1 / 0),
`hw/tb/tb_qb_core.sv` (`QBC_WSHP`, default 0), `impl/pnr/slice_bands.tcl` (`qb_class`: CREG-2 names -> `dec`).
Summaries: `results/r5d/` (`hist_*.md`, `viol_*.txt`, `pt_blk_r5dB_*.txt`, `pt_r5dB_ss_p3.0.txt`,
`summary_r5dB.txt`, `tb_core.txt`, `gls_r5dB.txt`).

```bash
# local (GPU 0): vectors + core bench
CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_core.py /tmp/root/qc18b/exc200/E6_s1/best.pt $V --images 7 123
QBC_DEFS="-DQBC_CREG=2 -DQBC_WTP=1 -DQBC_FTP=1 -DQBC_PPOP=1 -DQBC_BRG=2 -DQBC_WSHP=1" qc18bacc/hw/tb/run_tb_core.sh build
qc18bacc/hw/tb/run_tb_core.sh run $V/img7 $V/img123          # + -DQBC_MUT_DEC / _NNW / _G3N
# tau3, from /tmp/ckp908/qc18bacc/repo, QC_BUILD=/tmp/ckp908/qc18bacc/build
qc18bacc/impl/r5d/hist.sh r5c_B tt 2.0; qc18bacc/impl/r5d/hist.sh r5c_B ss 3.0
QC_TOPO=1 QC_HOOK=$PWD/qc18bacc/impl/r5a/topo_col.tcl QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" \
  QB_FL=$PWD/qc18bacc/impl/r5d/qb_blk_r5d.f qc18bacc/impl/run.sh all qb_col_blk 1.65 qb_col_blk_r5d_s20_tt_p1.65_topo
qc18bacc/impl/r5d/run.sh r5d_B qb_col_blk_r5d_s20_tt_p1.65_topo <r5a_vec/img0> <img1> <r5d_vec/img7> <img123>
# variants (tau6): QB_DEC_TOP=1 R5D_STEPS="pnr post gls" ... r5d_T ;  R5D_PNR_PERIOD=1.9 R5D_STEPS="pnr post gls" ... r5d_C
```
Results on tau: tau3 `syn/qb_col_blk_r5d_s20_tt_p1.65_topo`, `pnr/r5d_B` (route, DEF, SPEF tt / ss, PT, `gls/`),
`pnr/r5d_Bt0..15`, `r5d_Btiles`, `r5d/hist_*`, `sim/r5a_r5d_B`, `r5d_vec`; tau6 `pnr/r5d_T` (stopped before DR),
`pnr/r5d_C`, `syn/` netlist copy, `r5d_vec`.  tau3 `/tmp` 65 GB free, tau6 68 GB.  Nothing left running.

