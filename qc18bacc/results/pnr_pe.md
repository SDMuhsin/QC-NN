# Hardened PE block + column of 16 placed blocks (hierarchical P&R probe)

Labels as `results/pnr_slice2.md`: **[S]** static (DC / P&R geometry, PrimeTime with the def2spef SPEF, or OpenROAD's
own estimate where marked [OR est.]), **[R]** reasoning from [S] numbers.  Tools: DC 2024.09 topographical,
OpenROAD 2.0-12381, PrimeTime Q-2019.12; hosts tau5 (pe_b, column col_a*) and usask (pe_c', col_b*), build tree
`/tmp/ckp908/qc18bacc/build`.  Baseline: slice v2 (`qcs2_a`, flat strip): DC 702 344 um2, post-GRT 279 MHz [OR est.],
rows 0-8 + lanes ~460 MHz est., no detailed route.

**Stop-rule / box status.  Step 1 is complete: the PE block routes clean (0 DRC) at 508.3 / 309.6 MHz tt / ss
reg2reg [S, PT SPEF] (above the 450-MHz stop rule).  Step 2 is not: no column variant passed global route inside
the box (GRT-0119 in all of them), so there is no detailed route, no routed DRC count and no column PT sign-off.**
The last column numbers are post-global-route OpenROAD estimates with `-allow_congestion` (211 pins unrouted).
The last attempt (col_a7: 140-um spine, decoders and BR g fixed in spine windows) legalised.  It reached -1.49 ns
post-CTS (decode), but failed GRT with 46 k overflow markers, located where the decoders and BRs were moved to
(levels 2-5).  So the overflow follows the decode / broadcast cells, not the PEs.

**Answer to the hypothesis.**  Hardening fixes the PE side.  The block meets 508 MHz routed, against 279 MHz
post-GRT for the same logic in the flat strip.  With the blocks fixed in row order, no PE-internal path exists at
the top level, and the PE rows cannot be scrambled.  The top level shrinks from 213 k to 81 k placeable instances
(gpl 81 137).  In the column, the lanes stay where slice v2 had them, at -0.16 / -0.17 ns post-GRT
(~460 MHz [OR est.]).  The new limiter is the top level's own decode / broadcast cluster:

1. Global placement puts the decoders, the CREG port registers and both BR groups (~3.7 k + 1 k cells) together in
   the spine at levels 4-6.  BR group 0 sits ~500 um above the centre of its PE rows 0-7.
2. All 516-bit broadcasts and the decoder nets then cross that part of the spine.  The 100-um spine carries
   M2 / M4 / M6 / M8 vertically, and the blocks offer only M8 / M9.  Result: GRT-0119, with 26 k overflow
   gcells, 82 % of them over the blocks at levels 4-6.
3. The decode path `cdr -> qbc_dec -> BR` is D0 / D1 gates (DC-sized for 1.65 ns at the topographical spread)
   on 0.06-0.10 pF of spine wire.  It is -2.5 ns post-CTS.  A setup repair reaches -0.02 ns, but legalisation
   puts it back to -1.2 / -1.9 ns: upsized cells are displaced up to 191 um in the narrow spine (the §3 lesson
   of pnr_slice2.md, stronger here).
4. Post-GRT with the detours, the PE input pins are -0.49 ns.  The worst is BR g1 `c_q[24]` -> a DC CKBD1
   broadcast buffer -> 0.32 pF -> PE row 8 `c[24]`, with a 1.67-ns slew.  The decode is -4.66 ns.

So the measured mechanism moved from "PE rows scrambled by gpl" to "decode / BR cluster in a narrow spine".  The
mechanism is placement and floorplan again, not PE logic.


## 1. PE block `qb_pe_hb` [S]

`hw/rtl/qb_pe_hb.sv`: wrapper with the ports of `qbc_pe`, one instance `qbc_pe #(36, 20, 1, 1)` = exactly what
`qb_core` builds with CREG = PPOP = 1 (KB 36, ACC_W 20, CR 1, PP 1; `qb_core.sv` line 574).  No RTL changed.

| step | setting |
|---|---|
| DC | topographical, tt, **1.65 ns** (as the column), `compile_ultra -no_autoungroup -gate_clock -spg`; hook `impl/hard/topo_pe.tcl`: square, util 0.70, port sides = block pin sides; IO delays the column's 20 % (`impl/constraints.sdc`), outputs 0.05 pF (block-to-block wire, no repeaters over blocks) |
| floorplan | square, core = DC area / 0.65 (pe_b) or / 0.75 (pe_c), 2-um margin; pins: west `a` / `b2` (act edge), east `c` / `nnw` / `ctl` / `t2` / `fsh` / `wsh` / `clk` / `rst_n` (spine with BR), north `up` / `sh_in` (PE r + 4), south `shd` / `sh_out` (PE r - 4 / lanes) |
| layers | signal M2-M7 (M8 / M9 left to the column above the block).  **M2-M5 failed GRT-0119** (`pe_a`): overflow at the east / west pin edges (sources `c`, `a`), only M3 / M5 horizontal there |
| PDN | M1 rails, M4 straps, M7 straps to the boundary promoted to VDD / VSS pins (`pe_pdn.tcl`) |
| flow | timing-driven gpl, DRV repair of violating nets, CTS, one setup + one hold repair each legalised (`slice_post_cts.tcl`, `QB_RT_LOOPS 0`, IO latency shift 0), GRT (adj 0.25), DR 30 iter |
| sign-off | def2spef tt / ss / ff, PrimeTime at 2.0 ns (`pt_post_core.tcl`) |
| views | `write_abstract_lef -bloat_factor 0` (exact shapes: with `-bloat_occupied_layers` the M7 OBS covers the PG pins and no column via lands), ETMs: PrimeTime `extract_model -library_cell` on the routed netlist + SPEF, tt / ss / ff (`pe_etm.tcl`; OpenROAD `write_timing_model` exists but needs `read_spef`, which stops at def2spef's empty D_NETs) |

| quantity | pe_b (util 0.65) | pe_c (util 0.75, tau5) | pe_c' (same recipe, usask) |
|---|---|---|---|
| DC cell area (1.65 ns) | **25 542 um2**, 796 regs; pre-route PT 605.0 / 389.8 MHz tt / ss | same netlist | same |
| block (die) | 203.8 x 203.8 = **41 534 um2** | 189.4 x 189.4 = 35 872 | 35 872 |
| **block / DC** | **1.626** (core 1.549) | **1.404** (core 1.333) | 1.404 |
| cell area end / utilisation | 27 368 (x1.071) / 0.692 | 27 152 / 0.798 | 27 112 / 0.796 |
| routed DRC | **0** | 0 (DR slower: 956 markers at iter 6) | 2 |
| **PT SPEF fmax reg2reg tt / ss** | **508.3 / 309.6 MHz** | 501.1 / 304.4 | 496.3 / 300.4 |
| hold reg2reg tt / ss | +0.077 / +0.164 ns | | |
| clock latency (block-internal) tt / ss | 0.26 / 0.41 ns, skew 0.03 / 0.05 | | |
| P&R wall | 9 min | ~25 min | |

Critical path (all three, tt and ss): `g_pop2_g3n_p_reg` (S1 stem / g3n flag) -> weighted group sum -> 20-b
accumulator add -> `acc_reg` (S2) - the same logic class DC marks critical; tt / ss = 0.61 as pre-route
(605 / 390 = 0.64).  **Stop rule: the routed block is above 450 MHz tt (508.3), so step 2 ran.**
ss hold: 288 endpoints of the input `a -> a_q` paths are -0.05 ns at ss with the IO delay taken against the ideal
edge (0.41-ns internal latency); IO-only, column context decides (reg2reg hold positive).

Block vs flat: the PE routed alone reaches 508 MHz tt [S, PT] vs 279 MHz post-GRT [OR est.] for the same PE logic
in the flat strip (rows 11 / 14 / 15), and 0.85 x its own pre-route tt (605 at DC's 1.65-ns parasitics).

## 2. Column `qb_col_cwfp` with 16 `qb_pe_hb` blocks

### 2.1 Netlist [S]

DC topographical, tt, 1.65 ns, same RTL top `qb_col_cwfp` (CREG + WTP + FTP + PPOP).  Hook `impl/hard/col_hb.tcl`
removes the elaborated `qbc_pe_KB36_ACC_W20_CR1_PP1` and reads the block ddc.  It then `change_link`s the 16 PEs to
`qb_pe_hb` with dont_touch and no boundary optimisation, so the ports stay exact, and compiles the rest.

| | value |
|---|---|
| cell area | **700 149 um2** = 16 x 25 542 (PEs) + 291 471 glue; glue = lanes + banks 256 441, decoders + BR 15 865, top glue / CREG / buffers ~19 k (flat slice v2: 702 344) |
| pre-route PT tt / ss | 546.4 / 351.3 MHz.  Worst tt: `wsh_g -> PE shd` enable (block input `wsh` -> 160 shadow enables, inside the fixed block).  Worst ss: inside the PE |
| P&R netlist | `strip_blocks.py`: block modules removed (468 -> 450), PEs link to `qb_pe_hb` LEF + ETM (tt) |

The column DC run is deterministic: tau5 and usask gave the same area to the last digit.

### 2.2 Floorplan (`impl/hard/col.cfg`, `col_geom.tcl`, `col_pins.tcl`, `col_pdn*.tcl`, `col_place.tcl`)

* **2-wide stack, 8 levels**: level L = PE row 2L (west, R0) + row 2L + 1 (east, MY: block pins mirrored, act
  faces the die edge, BR pins face the spine).  Row r and r + 4 (shadow chain) sit two levels apart on the same
  side, and rows 0-3 sit directly above the lane band.  Blocks are fixed with a 4-um halo and 0 extra level gap.
* **Spine** between the stacks holds the CREG registers, decoders and both BR groups.  The broadcast span is 4
  levels (~850 um) instead of 8 PE bands (1.6 mm) in the strip.
* **Pins**: act / b2 of row r on the die edge beside PE r, west for even rows and east for odd rows.  (In the
  8-column core the act row bus crosses every column anyway, so an east tap is a feedthrough tap, not a new
  port.)  Codes / ctl / t2 / clk sit on top over the spine (+-60 um); lane stream / banks / PPU controls are
  along the bottom.
* **Lane band** height: lanes + banks at ~0.66-0.70 DC utilisation.
* **Routing** M2-M9: M8 / M9 over the blocks.
* **PDN**: M1 / M4 / M7 in the cell area, plus M8 straps over everything, dropping vias on the blocks' M7
  pins.  **The M8 straps must be >= 3 um wide.**  With 0.4-1.6 um, this OpenROAD build inserts no M7-M8 via at
  any crossing (PDN-0110 x 983, every block unconnected).  VDD passes `check_power_grid`.  VSS reports a few
  dangling M4 stubs in the inter-level halos.
* **Flow**: timing-driven gpl (density 0.75), then DRV repair of violating nets, then detailed placement, CTS,
  one setup repair + legalise, one hold repair + legalise (`slice_post_cts.tcl`, `QB_RT_LOOPS 0`), then GRT
  (adj 0.25), then DR.

### 2.3 Runs [S]

| run | blocks | spine / lane band | die | die / DC | outcome |
|---|---|---|---|---|---|
| col_a | pe_b | 56 / 780 | 489.6 x 2484.4 = 1.216 mm2 | 1.737 | DPL-0036 (882 spine cells: decoders 490, BR 72, CREG); with `-max_displacement 400` DPL ran > 60 min, killed |
| col_a2 (col_b: same, stopped) | pe_b / pe_c' | 56 | | | DPL-0036 again (839 cells, 388 decoders, 157 CREG): the 56-um spine is locally over-full.  4.2-4.5 k cells sat on block / halo areas after gpl + DRV repair; `col_place.tcl` now moves them into the spine before DPL |
| **col_a3** | pe_b | **100 / 740** | **533.6 x 2444.4 = 1.304 mm2** | **1.863** | DPL 32 s (spine rows 0.52 utilised); cells 377 057 um2 after CTS (glue x1.29); post-CTS -2.516 -> repair -0.023 -> legal -1.208 -> hold + legal **-1.871 ns** (decode); **GRT-0119** (26 216 overflow markers, 82 % over blocks at levels 4-6) |
| **col_b2** | pe_c' | 100 / 785 | **504.8 x 2374.2 = 1.198 mm2** | **1.712** | post-CTS repaired + legalised -0.733 (decode); **GRT-0119** (23 163 markers) |
| col_a4 | pe_b | 100 / 740 | 1.304 | 1.863 | BR / decoder windows applied after the DRV repair: place -6.76, post-repair -2.24 ns; stopped |
| col_a5 | pe_b | 100 / 740 | | | windows before the DRV repair (+-120 um BR, +-160 um decoders): DPL-0036 (311 decoder cells) |
| col_a7 | pe_b | **140 / 690** | 573.6 x 2394.4 = 1.373 mm2 | 1.961 | windows +-200 / +-300 um before the DRV repair, DPL 8 s (spine 0.58); place -1.79, post-CTS -1.85 -> repair -1.38 -> legal **-1.49 ns** (decode: `cdr -> dec -> NNw sum -> BR g0`, now D4-D16-sized: the NNw reduction over 36 decoders spread over 600 um + 500 um to BR g0); **GRT-0119, 46 403 markers**: levels 2-5 = the decoder / BR windows (spine 11.7 k, blocks 34.7 k) |
| col_a6 | pe_b | 100 / 740 | | | windows +-200 / +-300 um, DPL window 100 um: the DRV repair of the now-long decoder -> BR nets fills the spine to 0.78 (row area); DPL-0036 (> 1 000 cells) |

Area: the hard PEs alone cost x1.626 (pe_b) or x1.404 (pe_c) of their DC area.  The halos (4 um around 203.8 um)
add 8 %, and the spine 100 x 1.7 mm another ~0.17 mm2.  The column comes to die / DC **1.71-1.86**, against 1.506
for the flat strip, which had no complete route either [S].  The cheapest lever is the PE utilisation: pe_c
routes clean at 0.80 final utilisation and costs only -1.4 % tt (501 vs 508 MHz).

### 2.4 Timing [S, OR est.] (tt, 2.0-ns P&R clock, reg2reg, worst endpoint per class)

| class | post-CTS (repaired, legalised) col_a3 / col_b2 | post-GRT col_b2 (congestion allowed, 211 pins unrouted) |
|---|---|---|
| PE block internal | **508.3 / 501.1 MHz routed** (block PT SPEF, § 1) | same (fixed block) |
| top -> PE input pins (BR -> `c`, `up`, `fsh`) | none among the 3 000 worst endpoints | **-0.49 ns** (BR g1 -> CKBD1 -> 0.32 pF -> row 8 `c[24]`) |
| fused lanes | -0.02 / -0.05 | -0.17 (`s_rd` / `u_rin`) |
| wide lanes | | -0.16 (`y2`) |
| decode / BR (`cdr -> dec -> BR`) | **-1.87 / -0.73** | **-4.66** |
| hold reg2reg | +0.006 / +0.019 | -0.108 |

Lanes alone: ~460 MHz [OR est.], as slice v2.  PEs: 496-508 MHz routed [S].  Column post-GRT is decode-limited:
**~150 MHz [OR est., congested]**.  This number is a placement / route artefact of the spine.  It is not a
logic-depth limit: DC closes the same decode at 1.65 ns, and the repair reaches -0.02 ns before legalisation.

## 3. What would fix the column [R]

1. **Decode / broadcast demand, not position, is the limit**: col_a3 (gpl positions), col_a7 (fixed windows) and col_b2
   (smaller blocks) all overflow where the decoders / BRs sit.  Per group the spine has to carry 2 x 370 decoder ->
   BR bits, 8 x 516 BR -> PE pins and the 288 code bits, with only M8 / M9 over the blocks.  Options:
   - **one BR per PE level** (8 groups instead of 2: +6 x 516 = 3.1 k flops, ~+20 k um2 = +3 % per column [R]), placed
     at its level, so the 516-bit broadcast only spans one level (it still costs fewer flops than the 5 783 that CREG
     saved);
   - decode inside every PE block (only `cd` / `ctl` / `t2` on the spine) would replicate the ~9.6 k um2 of
     decoders 16 x (~+150 k um2, +21 % [R]): too costly;
   - **harden decoder + BR as a spine block** with its pins on M8.
2. **Spine routing capacity**: put the BR -> PE broadcast on M8 over the blocks (pins of `c` on M8 in a strip of the
   block's spine edge), or widen the spine where the decoders sit only.
3. **Repair at global-route parasitics, then incremental legalisation with a bounded window**: the post-CTS loss is
   legalisation of upsized decoder cells in a 100-um-wide spine.
4. PE block: use pe_c (util 0.75), -14 % block area for -1.4 % fmax.

## 4. Files and commands

New: `hw/rtl/qb_pe_hb.sv`, `hw/rtl/qb_hb.f`; `impl/hard/` (`topo_pe.tcl`, `pe.cfg`, `pe_pins.tcl`, `pe_pdn.tcl`,
`sdc_pnr.tcl`, `pe_post.sh`, `pe_etm.tcl`, `col_hb.tcl`, `strip_blocks.py`, `col.cfg`, `col_geom.tcl`,
`col_pins.tcl`, `col_pdn.tcl`, `col_pdn_macro.tcl`, `col_place.tcl`, `col_post.sh`, `pt_col.tcl`).  Changed:
`impl/run.sh` (`QB_FL` filelist), `impl/pnr/grt_est.tcl` (`QB_GRT_ARGS`, class `creg`).  No RTL behaviour changed.

```bash
B=/tmp/ckp908/qc18bacc/build
QB_FL=$PWD/qc18bacc/hw/rtl/qb_hb.f QC_TOPO=1 QC_HOOK=$PWD/qc18bacc/impl/hard/topo_pe.tcl \
  QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" qc18bacc/impl/run.sh all qb_pe_hb 1.65 qb_pe_hb_tt_p1.65_topo
QB_CFG=../hard/pe.cfg QB_PNR_PERIOD=2.0 [QB_HB_UTIL=0.75 QB_DENS=0.85] qc18bacc/impl/pnr/run.sh pnr pe_b   # pe_c
qc18bacc/impl/hard/pe_post.sh pe_b          # SPEF ss/ff, PT tt/ss, abstract LEF, ETMs tt/ss/ff
QB_HB_DDC=$B/syn/qb_pe_hb_tt_p1.65_topo/qb_pe_hb.ddc QB_FL=... QC_TOPO=1 QC_HOOK=$PWD/qc18bacc/impl/hard/col_hb.tcl \
  QC_COMPILE=... qc18bacc/impl/run.sh all qb_col_cwfp 1.65 qb_col_cwfp_hb_tt_p1.65_topo
E=$B/pnr/pe_b/out; QB_CFG=../hard/col.cfg QB_PNR_PERIOD=2.0 QB_HB_LEF=$E/qb_pe_hb.lef QB_HB_LIB=$E/etm/qb_pe_hb_tt.lib \
  QB_SPINE=100 QB_HL=740 QB_DPL_ARGS="" qc18bacc/impl/pnr/run.sh pnr col_a3
cp db/cts_rt.odb db/cts_drv.odb; cp db/cts.sdc db/cts_drv.sdc   # in the run dir, then:
QB_GRT_ARGS=-allow_congestion <same env> qc18bacc/impl/pnr/run.sh est col_a3
QB_HB_ETM_DIR=$E/etm qc18bacc/impl/hard/col_post.sh <tag>   # after a complete route (not reached)
```

