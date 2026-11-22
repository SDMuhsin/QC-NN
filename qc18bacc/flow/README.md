# qc18bacc implementation flow

Stage-organized implementation flow of the qc18bacc chip (column block, act block, hub block, chip top) on TSMC 65 nm
(OpenROAD P&R through the shared `flow/tsmc65`, PrimeTime, Calibre). It replaces the round directories `impl/r4 .. r46`
(R47 refactor, behaviour-preserving; history of every round stays in `results/*.md` and in git).

## Layout

| dir | contents |
|---|---|
| `common/` | `env.sh` (bash: `QBF`, `ROOT`, `B`, `TOOLS`, `PY`, `OR`, `qb_kit`), `qb.tcl` (Tcl: `::QBF`, `qb_env`), `or.sh` (run an OpenROAD script in a run dir), `block_sdc.tcl` (netlist + P&R SDC of a hard block from its DC run), `constraints.sdc` (DC / PT SDC), `queue.sh` (detached step queue per host), `status.sh` (run status digest) |
| `synth/` | DC / partition / top-netlist steps that produced the P&R input netlists |
| `floorplan/` | pins, PDN, macro placement, floorplan generators |
| `place/` | placement hooks (seeds, tiling, buffer removal, incremental gpl) |
| `cts/` | pre-CTS hooks (ICG sizing / splitting), clock balancing |
| `route/` | global / detailed route hooks and drivers (`dr.sh`), re-route |
| `repair/` | post-CTS repair (`post_cts.tcl`), post-route hold ECO (`hold_eco.sh` / `.tcl`), antenna repair |
| `icc2/` | IC Compiler II steps (R54): `common.tcl` (kit + block config, `qb_open` / `qb_done` / `qb_qor`), `libs.tcl` (std-cell NDM, icc2_lm_shell), `init.tcl` (design library, TLU+, netlist, MCMM, SDC), `floorplan.tcl`, `place.tcl`, `cts.tcl`, `route.tcl`, `outputs.tcl`; block facts in `blocks/<b>/icc2.cfg` |
| `signoff/` | `spef.sh`, `antenna.tcl` (LEF-rule antenna check); `pt/` PrimeTime; `etm/` abstracts, ETMs, antenna data in LEFs; `calibre/` GDS, LVS source, Calibre DRC / LVS / antenna |
| `blocks/<b>/` | per design: `<b>.env` (parameters), `<b>.cfg` (the one OpenROAD design config), `run.sh` (steps), design data |

Every block / top is run from the repository root of a host-local copy of the repository on the build server
(`QC_BUILD` default `/tmp/$USER/qc18bacc/build`, tools in `QC_TOOLS` default `/tmp/$USER/tools`, kit paths in the
untracked `flow/tsmc65/site/*` files). P&R runs land in `$QC_BUILD/pnr/<tag>`.

Unattended runs (R50): `common/queue.sh <logdir> <spec>` runs `blocks/<b>/run.sh` steps one after the other in a
detached session (setsid + nohup; kill the queue with `kill -- -<pgid>`), one spec line per step
`<wait> [VAR=val ...] <blk> <step> <run> [args]` (`<wait>`: `-` or `pid:N`, `file:PATH`, `grep:PATH:PAT`,
`need:PATH:PAT`, comma-separated); it stops at the first failure and keeps `<logdir>/queue.state` (n blk step run
status start end rc) and `q<n>_<blk>_<step>.out`.  One queue per host keeps one heavy job per host (30 GB).
`common/status.sh <run_dir|tag>...` prints at most 15 lines per run: current step + elapsed, latest DRT iteration +
markers, PT setup / hold / DRV per corner, last ERROR line, queue.state of the run.

Exit status (R53): `synth/run.sh` + `partition.sh` (flow/tsmc65 `run_dc.sh` / `run_pt.sh`), the PrimeTime and Calibre
parts of `blocks/*/run.sh` and `signoff/calibre/*.sh` exit non-zero when the tool fails (PrimeTime: exit status or an
`^Error` line in its log or `parasitics_command.log`, `common/env.sh qb_pt`; background jobs: `qb_wait`), so a queue
stops at that step.  The OpenROAD steps are unchanged.

## Column block qb_col_blk (`blocks/col`, ICC2 since R54, results/r54.md)

```
qc18bacc/flow/blocks/col/run.sh pnr <tag>       # ICC2 libs init floorplan place cts route outputs -> $QC_BUILD/icc2/col/<tag>
qc18bacc/flow/blocks/col/run.sh post <tag>      # PT tt/ss/ff at 6.5 ns on the ICC2 netlist + SPEF, ETMs
qc18bacc/flow/blocks/col/run.sh calibre <tag>   # LVS source, Calibre LVS / DRC (block deck) / antenna on the ICC2 GDS -> <run>/calibre
```
Inputs: netlist + SDC `$B/syn/qb_col_blk_r5d_s20_tt_p1.65_topo` (P&R SDC: common/block_sdc.tcl + blocks/col/io_budget.tcl
at 5.0 ns), pin positions from the r48 column DEF (`COL_PIN_DEF`). Parameters: `col.env`, `icc2.cfg`.  The OpenROAD
config `col.cfg` / `route_pre.tcl` (OpenROAD, R48) were deleted in R54 (git history).

## Act block qb_act2_blk (`blocks/act`, production lineage r35_act -> r38_act_rr2)

```
qc18bacc/flow/blocks/act/run.sh pnr <tag>              # floorplan .. place .. CTS (db/cts.odb)
qc18bacc/flow/blocks/act/run.sh postcts <src> <tag>    # re-spread + post-CTS repair -> db/cts_rt.odb
qc18bacc/flow/blocks/act/run.sh route <src> <tag>      # GRT, antenna repair, DR, finish
qc18bacc/flow/blocks/act/run.sh drveco <tag>           # PrimeTime DRV ECO ss + tt -> out/drv_eco_tt.tcl (applied by hold)
qc18bacc/flow/blocks/act/run.sh hold <tag>             # DRV + hold repair at tt + ss, full re-route (repair/hold_eco.sh)
qc18bacc/flow/blocks/act/run.sh post <tag>             # SPEF, PT, antenna, abstract + ETMs, antenna data, ring LEFs -> $B/r9a_blk/<tag>
qc18bacc/flow/blocks/act/run.sh calibre <tag>          # GDS, LVS source, Calibre LVS / DRC / antenna
```
Production (R50): `pnr r48_act_p; postcts r48_act_p r48_act_s; route r48_act_s r48_act; post; hold; post; calibre`
(results/r48.md - r50.md: DRT-0218 fixed by route/pa_reset.tcl, R49; RSZ-0050 and the tt + ss repair session, R50).
The R37 / R38 lineage steps eco1 / eco6 / reroute (r35_act_c -> r38_act_rr2) were removed in R50 (git history).  Inputs: `$B/syn/r35_act`, `$B/r35/col_act_pins.txt` (synth/run.sh act / actpins).

## Hub block qb_hub (`blocks/hub`, production lineage r35_hubC -> r38_hub_rr -> r40_hub)

```
qc18bacc/flow/blocks/hub/run.sh all <tag>               # gate prod dio dr fin antd pt (run34.sh all)
qc18bacc/flow/blocks/hub/run.sh copy <src> <tag>        # copy of a run for a hold round (replaces the manual copies)
qc18bacc/flow/blocks/hub/run.sh drveco <tag>            # PrimeTime DRV ECO ss + tt -> out/drv_eco_tt.tcl (applied by hold)
qc18bacc/flow/blocks/hub/run.sh hold <tag> [0.05]       # setup pre-repair + DRV + hold at tt + ss, full re-route (HUB_HOLD_DT, HUB_HOLD_ANT, QB37_RESIZE)
qc18bacc/flow/blocks/hub/run.sh signoff <tag>           # SPEF, fin, antenna, PT, antenna LEF, ring LEF, ETM scan, GDS, LVS, Calibre antenna
```
(R37 incremental ECO / R38 reroute steps removed in R50, git history.)  Inputs: `$B/syn/r26_ptr`, partition `$B/r26_w` (synth/run.sh chip / part), column abstract `$B/r5b_blk`, SRAM views.
`signoff` makes the SRAM LVS stubs and abstract GDS from the run's macro LEFs in `$B/drc/<tag>/sram` (lefstub.py,
`signoff/calibre/kl.sh kl_abs`; R53, was the tau6-only `$B/drc/r38_hub`).

## Chip top qb_chip (`blocks/top`, production run r43_a + R46 opt-ins)

```
qc18bacc/flow/blocks/top/run.sh views           # block views TOP_ABS from the block runs named in top.env (R48)
qc18bacc/flow/blocks/top/run.sh fp <tag>        # init, macro dump, floorplan/top_fp.py, floorplan + PDN, power-grid check
qc18bacc/flow/blocks/top/run.sh pnr <tag>       # place .. GRT + post-GRT repair -> db/grt.odb + route.guide
qc18bacc/flow/blocks/top/run.sh hold <tag>      # post-GRT hold + antenna repair in a fresh process (repair/top_hold.tcl)
qc18bacc/flow/blocks/top/run.sh dr <tag>        # detailed route + finish, SPEF tt + ss
qc18bacc/flow/blocks/top/run.sh antenna <tag>   # LEF-rule antenna check
qc18bacc/flow/blocks/top/run.sh pt <tag> [tt ss]  # PrimeTime per corner
qc18bacc/flow/blocks/top/run.sh lvs <tag>       # Calibre LVS (blocks / SRAMs as LVS BOX)
```
Inputs: `$B/r35/top_r35.v` (synth/run.sh topnl), `$B/syn/r35_ptr`, the block outputs named in `top.env`.

## Inputs: netlists, partition, top netlist (`synth/`)

```
qc18bacc/flow/synth/run.sh col              # column DC -> syn/qb_col_blk_r5d_s20_tt_p1.65_topo
qc18bacc/flow/synth/run.sh act [r35_act]    # act DC (S1T) -> syn/r35_act
qc18bacc/flow/synth/run.sh chip <tag>       # chip DC -> syn/r26_ptr (hub partition source), syn/r35_ptr (top)
qc18bacc/flow/synth/run.sh part <syn> <dir> # hub partition -> $B/r26_w (hub P&R), $B/r35_w (top)
qc18bacc/flow/synth/run.sh topnl r35_w      # top netlist -> $B/r35/top_r35.v (+ bpins / equiv / actmap)
qc18bacc/flow/synth/run.sh actpins          # $B/r35/col_act_pins.txt (act pins aligned to the column abstract)
qc18bacc/flow/synth/run.sh macros           # ARM SRAM views
```
These steps were moved path-only from their rounds (not re-run in R47; DC is not part of the equivalence proof). Not
recorded at the time and reconstructed from logs: the act DC (`$B/r35_actsyn.out`), the r35_ptr chip DC (`$B/r35_syn.out`),
`col_act_pins.txt`. Frozen artifacts with no producer in this flow: `$B/r5d_Ctiles` (PE tiles of the R5d column run) and
`$B/r5b_blk` (reference column abstract + ETMs of R5b; `git show c9ea93f:qc18bacc/impl/r5b/run.sh` blk step), the hub
`r37_ssx*_ports.txt` port lists (R37, partly hand-edited).

## R47 equivalence proof (old impl/ vs this flow, on tau)

OpenROAD global placement is not run-to-run deterministic with several threads (the HEAD code rerun differs from the
reference r35_colb placement: 223 228 vs 223 211 instances; Nesterov HPWL differs from iteration 10). Every proof therefore
ran old (HEAD c9ea93f snapshot) and new with `QC_PNR_THREADS=1`, with a wrapped openroad that logs every sourced file and
every key OpenROAD / SDC command with its arguments (`/tmp/ckp908/r47` on tau: tools wrapper, trace prelude, odb dump,
`cmp.sh`).  Steps that were not run were checked with a local dry run (logging stubs for openroad / python3 / tcsh /
calibre / v2lvs) comparing the resolved tool command lines.

| design | run on tau, 1 thread | command trace | odb dump | other |
|---|---|---|---|---|
| col | init .. place; CTS + post-CTS repair + GRT + antenna repair from the same place.odb (stopped at DR) | 54 118 / 37 124 cmds, 0 diff | place 86dc228eb6b1, cts 0a9b0e9d0fa9, cts_rt 13600551309d identical | P&R SDC, route.guide, all reports identical |
| act | init .. place, CTS, post-CTS (re-spread + repair) | 28 858 cmds, 0 diff (postcts: 3 repair_timing calls logged unwrapped) | place a83cf02670ee, cts 7a122e1cfcc8, cts_rt fe1cd5eaf69b identical | P&R SDC, reports identical |
| hub | gate: fp .. place + gate GRT | 277 175 cmds, identical apart from the 10 deleted report-only diagnostics | place 45849f73bad4 identical | mplace.tcl, pins9_data.tcl, cfg SDC / hub_io.tcl, route.guide identical |
| top | fp (16 threads) + place (1 thread from the same pdn.odb) | 2 610 cmds, 0 diff | pdn f81b3d3078fa, place bb32facf682b identical | mplace.tcl, macros.txt, P&R SDC identical |

Final regression of the finished tree (all four designs, 1 thread, after every edit): db/place.odb dumps identical to the
old runs above (col 86dc228eb6b1, act a83cf02670ee, hub 45849f73bad4, top pdn f81b3d3078fa / place bb32facf682b).

Dry-run checked only (not run on tau): col post / views / calibre; act route, ECOs, reroute, hold, post, calibre; hub prod ..
signoff; top hold, dr, antenna, pt, lvs, views (views reproduced abs7 byte-for-byte on tau4); synth (path-only moves).

## Old script -> new location
| old (qc18bacc/impl/) | new (qc18bacc/flow/) |
|---|---|
| constraints.sdc | common/constraints.sdc |
| hard/col_pdn.tcl | floorplan/pdn_m8.tcl |
| hard/pe_pdn.tcl | floorplan/pe_pdn.tcl |
| pnr/gpl_incr.tcl | place/gpl_incr.tcl |
| pnr/slice3_post_grt.tcl | route/col_post_grt.tcl |
| pnr/slice_bands.tcl | floorplan/col_bands.tcl |
| pnr/slice_post_cts.tcl | repair/post_cts.tcl |
| pt_hook.tcl | synth/pt_hook.tcl |
| r10b/grt.tcl | route/hub_gate_grt.tcl |
| r11/classes.tcl | route/top_classes.tcl |
| r11/top_nl.py | synth/top_nl.py |
| r13/pins.tcl | floorplan/act_pins.tcl |
| r13/qb_act2_blk.sv | synth/act_blk.sv |
| r14/bal14.tcl | cts/top_balance.tcl |
| r14/clk14.tcl | cts/top_clk_measure.tcl |
| r14/cts14.tcl | cts/top_clock_tree.tcl |
| r14/drv_post.tcl | route/top_drv_post.tcl |
| r14/fp14.py | floorplan/top_fp.py |
| r14/split14.tcl | place/top_split.tcl |
| r20/qb_act2_blk_chip_s1t.f | synth/act_blk.f |
| r21/abs.tcl | signoff/etm/hub_abs.tcl |
| r21/ant.tcl | signoff/hub_check_ant.tcl |
| r21/pt_hub.tcl | signoff/pt/hub.tcl |
| r29/antd29.tcl | signoff/antenna.tcl |
| r31/pt31.tcl | signoff/pt/hub_summary.tcl |
| r34/cts_pre.tcl | cts/hub_cts_pre.tcl |
| r35/blkant.py | signoff/etm/blkant.py |
| r35/blkant.tcl | signoff/etm/blkant.tcl |
| r35/colpins.py | floorplan/abstract_pins.py |
| r35/etmcheck.py | signoff/etm/etmcheck.py |
| r35/hold35.tcl | repair/hold_eco.tcl |
| r35/pt_top_sdc.tcl | blocks/top/pt_sdc.tcl |
| r36/cal36.sh | signoff/calibre/cal.sh |
| r36/gds_merge36.py | signoff/calibre/gds_merge.py |
| r36/pdn36.tcl | floorplan/top_pdn.tcl |
| r37/hubio37.tcl | repair/hub_io.tcl |
| r37/hubpre37.tcl | repair/hub_setup_pre.tcl |
| r37/icgclone37.tcl | deleted in R48 (ICG split before CTS, cts/icg_pre.tcl) |
| r37/inbuf37.tcl | repair/act_hold_pre.tcl (removed R50) |
| r37/pt37.tcl | signoff/pt/hub_signoff.tcl |
| r38/drc_blk.sed | signoff/calibre/drc_blk.sed |
| r38/drc_xsram.sed | signoff/calibre/drc_xsram.sed |
| r38/gds38.sh | signoff/calibre/gds.sh |
| r38/klrun.py | signoff/calibre/klrun.py |
| r38/lef2gds.py | signoff/calibre/lef2gds.py |
| r38/lefstub.py | signoff/calibre/lefstub.py |
| r38/lvs_case.sed | signoff/calibre/lvs_case.sed |
| r38/lvs_hub.sed | signoff/calibre/lvs_hub.sed |
| r38/lvs_hubpg.sed | signoff/calibre/lvs_hubpg.sed |
| r38/lvssrc38.sh | signoff/calibre/lvs_src.sh |
| r38/pgfix.py | signoff/calibre/pgfix.py |
| r38/reroute38.tcl | route/reroute.tcl (removed R50) |
| r4/constraints.sdc | synth/chip_constraints.sdc |
| r4/dc_hook.tcl | synth/chip_macros_hook.tcl |
| r4/dc_post.tcl | synth/chip_dc_post.tcl |
| r4/macros.txt | synth/macros.txt |
| r4/pt_class.tcl | synth/chip_pt_class.tcl |
| r43/autol43_or.tcl | repair/top_io_latency.tcl |
| r43/etm43.py | deleted in R48 (ETM without input driving cells) |
| r43/hold43.tcl | repair/top_hold.tcl |
| r43/keepout43.tcl | place/keepout.tcl |
| r44/icgsplit44.tcl | cts/icg_split.tcl |
| r46/etmochk46.py | signoff/etm/etm_nooutchk.py |
| r5a/budget.tcl | blocks/col/io_budget.tcl |
| r5a/drc_hist.py | signoff/drc_hist.py |
| r5a/etm.tcl | signoff/etm/etm.tcl |
| r5a/pins.tcl | floorplan/col_pins.tcl |
| r5a/pt_blk.tcl | signoff/pt/col_blk.tcl |
| r5a/topo_col.tcl | synth/col_dc_hook.tcl |
| r5b/core_blk.sv | synth/chip_core_blk.sv |
| r5b/dc_hook.tcl | synth/chip_dc_hook.tcl |
| r5b/dump_macros.tcl | floorplan/dump_macros.tcl |
| r5b/gen.sh | synth/chip_gen.sh |
| r5b/lef_ring.py | signoff/etm/lef_ring.py |
| r5b/pdn.tcl | floorplan/pdn_chip.tcl |
| r5b/pdn_macro.tcl | floorplan/pdn_macro.tcl |
| r5b/pre_place.tcl | place/rm_buffers.tcl |
| r5d/qb_blk_r5d.f | synth/col_blk.f |
| r5e/macros.txt | synth/macros_fc.txt |
| r6a/cuts.py | synth/part_cuts.py |
| r6c/icg.tcl | cts/icg_size.tcl |
| r7b/etm_fix.py | deleted in R48 (ETM without input driving cells) |
| r7c/budget.tcl | blocks/act/io_budget.tcl |
| r7c/col_pins.py | synth/col_act_pins.py |
| r7c/pt_blk.tcl | signoff/pt/act_blk.tcl |
| r8/dr.tcl | route/dr.tcl |
| r8b/pt_s1.tcl | synth/act_pt_classes.tcl |
| r9a/abs.tcl | signoff/etm/act_abs.tcl |
| r9a/lef_size.py | signoff/etm/lef_size.py |
| r9a/place.tcl | place/act_edge.tcl |
| r9a/route_rt.tcl | route/act_route.tcl |
| r9a/topo.tcl | synth/act_dc_hook.tcl |
| r9b/bnd.py | synth/part_bnd.py |
| r9b/const.py | synth/part_const.py |
| r9b/dc_part.tcl | synth/part_dc.tcl |
| r9b/dump.tcl | synth/part_dump.tcl |
| r9b/part.py | synth/part_hub.py |
| r9b/pins9.py | floorplan/hub_pins.py |
| r9b/ports.tcl | synth/part_ports.tcl |
| r9b/post_grt.tcl | route/grt_stop.tcl |
| r9b/route_pre.tcl | route/postcts_grt.tcl |
| r9b/sdc.py | blocks/hub/sdc.py |
| pnr/slice.cfg pnr/slice3.cfg r5a/col.cfg r5c/col.cfg r35/col.cfg | blocks/col/col.cfg (netlist / P&R SDC part: common/block_sdc.tcl) |
| r35/run35.sh (col, colfrom, colpost) r5a/post.sh pnr/run.sh (pnr, spef) | blocks/col/run.sh; spef step -> signoff/spef.sh; abstract heredoc -> signoff/etm/col_abs.tcl |
| r35/col_pins.tcl | floorplan/col_pins.tcl |
| pnr/slice3_place.tcl r5c/place.tcl r5c/spread.tcl | place/col_place.tcl |
| r35/col_route_pre.tcl | blocks/col/route_pre.tcl + route/gadj_layers.tcl (one per-layer GRT adjustment wrapper for every design) |
| r29/or29.sh | common/or.sh |
| r35/run35.sh (hold) | repair/hold_eco.sh |
| r8/run.sh (dr) | route/dr.sh |
| r20/act.cfg r19/act.cfg r16/act.cfg r13/act.cfg r9a/act.cfg r7c/act.cfg pnr/slice.cfg | blocks/act/act.cfg |
| r35/run35.sh (act, actabs, hold) r20/run.sh r19/run.sh r16/run.sh r9a/run.sh r38/hold38.sh (act) r38/fin38.sh (act) | blocks/act/run.sh |
| r9a/place.tcl r13/pad.tcl | place/act_edge.tcl |
| r19/place.tcl r19/band.tcl r20/place.tcl r13/place.tcl r7c/gpl_incr2.tcl | place/act_place.tcl |
| r16/respread.tcl r16/post_cts.tcl r13/post_cts.tcl r9a/post_cts.tcl | repair/act_post_cts.tcl |
| r35/act_io.tcl | repair/block_io.tcl (R50: generic, was repair/act_hold_io.tcl) |
| r37/inbuf37.tcl r37/actpre37.tcl | repair/act_hold_pre.tcl (removed R50) |
| r10b/hub.cfg r9b/hub.cfg r22/run.sh (QC_PNR_SET) r34/preset.env | blocks/hub/hub.cfg + blocks/hub/hub.env |
| r34/run34.sh r34/preset.env r31/run31.sh r28/run28.sh r22/run.sh r21/run.sh r15/run15.sh r29/run29.sh r31/pt31.sh r37/pt37.sh r40/fin40.sh r38/hold38.sh (hub) r38/fin38.sh (hub) | blocks/hub/run.sh |
| r22/mplace22.py r15/mplace15.py r10b/mplace10.py r9b/mplace9.py | floorplan/hub_mplace.py |
| r10b/pins10.tcl r9b/pins9.tcl | floorplan/hub_pins.tcl |
| r35/hub_place_pre.tcl r21/place_pre.tcl r10b/place_pre.tcl r9b/place_pre.tcl | place/hub_place_pre.tcl |
| r15/grt15.tcl r10b/grt.tcl | route/hub_gate_grt.tcl |
| r34/cts_pre.tcl r9b/cts_pre.tcl | cts/hub_cts_pre.tcl |
| r34/route_pre.tcl r21/route_pre.tcl | route/hub_route_pre.tcl |
| r24/pc24.tcl r24/fix24.tcl r24/dump24.tcl | repair/hub_post_cts.tcl |
| r34/post_grt.tcl r21/post_grt.tcl | route/hub_post_grt.tcl |
| r29/dio29.tcl r34/dio_pre.tcl r29/pdn29.tcl r31/buf31.tcl | route/hub_diodes.tcl |
| r38/hpost38.tcl | repair/hub_hold_ant.tcl |
| r36/top.cfg r35/top.cfg r14/top14.cfg r11/top.cfg r5b/chip.cfg hard/sdc_pnr.tcl | blocks/top/top.cfg |
| r36/top_sdc.tcl r35/top_sdc.tcl r11/top_sdc.tcl | blocks/top/top_sdc.tcl |
| r36/pt_top_sdc.tcl r35/pt_top_sdc.tcl | blocks/top/pt_sdc.tcl |
| r39/run39.sh r36/run36.sh r35/run35.sh (tfp, tpnr, tdr, tpt) r42/lvs42.sh /tmp/ckp908/r43_env_a.sh /tmp/ckp908/r43_pt.sh | blocks/top/run.sh + blocks/top/top.env |
| r14/fp14.py r11/lefio.py | floorplan/top_fp.py |
| r11/pins.tcl | floorplan/top_pins.tcl |
| r14/pre_place14.tcl | place/top_place.tcl |
| r43/cts_pre43.tcl | cts/top_cts_pre.tcl |
| r14/route_pre14.tcl | route/top_route_pre.tcl |
| r14/post_grt14.tcl r35/top_post_grt.tcl r35/shim/post_grt.tcl | route/top_post_grt.tcl |
| r36/pc_none.tcl | repair/post_cts_none.tcl |
| r43/ant43.tcl | repair/top_antenna.tcl |
| r5b/pt_chip.tcl r43/autol43_pt.tcl r42/pt42x.tcl r39/pt39x.tcl | signoff/pt/top_chip.tcl |
| r36/etmdb.sh | deleted in R48 (ETM without input driving cells) |
| r36/gds36.sh | signoff/calibre/gds.sh (top LVS now uses the shared GDS step) |
| run.sh | synth/dc.sh |
| r4/run.sh | synth/chip_dc.sh |
| r26/run26.sh (syn, part) r5b/run.sh (syn) r20/run.sh (syn) r35/run35.sh (part, nl) r9a/run.sh (pins) | synth/run.sh |
| r10b/run.sh (dump part ports sdc) r9b/run.sh (dump part ports sdc) | synth/partition.sh |
| r9a/topo.tcl r13/topo.tcl r20/topo.tcl | synth/act_dc_hook.tcl |

## Deleted without a successor (git history is the archive: `git show c9ea93f:qc18bacc/impl/<path>`)

One-off diagnostics, probes, superseded rounds and opt-ins no production flow uses.  Not regenerated by this flow (frozen
inputs): the PE tiles `$B/r5d_Ctiles` (r5d/run.sh tiles, r5c/pe_tile.cfg, r5c/place_dump.tcl, hard/pe_pins.tcl), the
column reference views `$B/r5b_blk` (r5b/run.sh blk, r5a/post.sh) and the top's column views `$B/r36/abs4` (run36.sh abs,
r5b/etm_ins.py).  R44 / R45 fix candidates that are not in production yet (e.g. r45/lef57db45.tcl, r45/etmnodrv45.tcl) are
deleted too; R48 took them from commit 2f4055b.

## R48 additions (results/r48.md)
| file | what |
|---|---|
| route/drc_rules.tcl | kit min-step / EOL rules written into the tech before every detailed_route (was r45/lef57db45.tcl) |
| repair/drv.tcl | max-transition / max-cap repair (qb_drv, qb_drv_grt) after CTS, hold insertion, GRT |
| cts/icg_pre.tcl | ICG split (QB44_SPLIT 400) + sizing / move before CTS in every design |
| cts/clk_lat.tcl | measured insertion delay L (p50 clock-pin latency) for the IO budget shift |
| signoff/pt/common.tcl | PT: per-corner L (out/clk_lat_<c>.txt), DRV counts, ETM input context (was r45/etmnodrv45.tcl) |
| signoff/etm/etm_ins.py | column ETM + measured insertion arcs for the top (was r5b/etm_ins.py) |

- `r4/` (19): area_summary.py, core_stub.sv, dat_energy.sh, dat_energy.txt, dc_rpt.tcl, gls.sh, macro_counts.py, macros_d.txt, nocore.sh, power.py, prog_shapes.txt, pt_power.tcl, pwr.sh, qb_chip_tech_flops.f, saif_fix.py, saif_scale.py, saif_window.py, seq.f, seq_m.f
- `r4b/` (13): exp/rot.f, exp/rot.sv, exp/t2p.f, exp/t2p.sv, exp/tb_rot.sv, exp/wb.f, exp/wb.sv, exp/wby.f, exp/wby.sv, reg_audit.tcl, sdc_chk.sdc, seq.sdc, seq_rt.f
- `r5a/` (5): corr.py, density.tcl, gls.sh, guide_map.py, repin.tcl
- `r5b/` (6): area.tcl, cts_drv.tcl, est_classes.tcl, etm_ins.py, grt_probe.tcl, mplace.py
- `r5c/` (3): pe_tile.cfg, place_dump.tcl, spread_db.tcl
- `r5d/` (4): hist.py, hist.sh, hist.tcl, run.sh
- `r5e/` (5): ddc_area.sh, ddc_area.tcl, head_slack.py, shapes_fc128.txt, sweep_fc128_raw.txt
- `r6a/` (4): net_dump.tcl, net_trace.tcl, syn.sh, trace_sum.py
- `r6b/` (15): buf_hist.tcl, chip.cfg, cts_pre.tcl, dpl_probe.tcl, dpl_probe2.tcl, grp_place.tcl, icg_geom.tcl, icg_probe.tcl, mplace.py, pins.tcl, place.tcl, prep.tcl, pt_extra.tcl, run.sh, spread.tcl
- `r6c/` (16): chip.cfg, cts_pre.tcl, dr.tcl, est_rc.tcl, place.tcl, post_grt.tcl, probe_bins.tcl, probe_clk.tcl, probe_fail.tcl, probe_rows.tcl, route_pre.tcl, run.sh, snap3.tcl, spread3.tcl, t_snap3.tcl, t_spread3.tcl
- `r7a/` (3): classify.py, dump_grt.tcl, obs.tcl
- `r7b/` (11): blklat.tcl, chip.cfg, classes.tcl, cts_pre.tcl, groups.py, ovf.py, place.tcl, post_grt.tcl, run.sh, slice.py, xslice.py
- `r7c/` (8): cong_cls.py, etm_dc.tcl, grt_probe.tcl, pins.tcl, qb_act2_blk.f, qb_act2_blk.sv, run.sh, topo_act.tcl
- `r7d/` (4): hqs.sv, rot.sv, syn.sh, wb_srd.sv
- `r7e/` (4): dc.sh, wbs.sv, wbs_top.sv, wbz.sv
- `r7g/` (2): rfsp_bb.sv, syn.sh
- `r8/` (7): chip.cfg, classify_win.py, groups.py, mplace.py, ovf.py, pgrp.py, probe_west.tcl
- `r8a/` (4): pt_paths.tcl, pt_xtra.tcl, run_pt.sh, syn.sh
- `r8b/` (5): cong_cls.py, model.py, qb_act2_blk_s1m1.f, qb_act2_blk_s1m2.f, run.sh
- `r8c/` (3): model.py, qb_act2_blk_s2m.f, run.sh
- `r8d/` (6): dc_grp.tcl, pt_lat.tcl, pt_xtra.tcl, run_pt.sh, run_pt_lat.sh, syn.sh
- `r9a/` (2): pins.tcl, qb_act2_blk.f
- `r9b/` (7): cone.py, dumpdb.tcl, equiv.py, guide9.py, netcls.tcl, ovf9.py, place_fix.tcl
- `r9c/` (1): syn.sh
- `r10b/` (9): grt_probe.tcl, launch/probe.sh, launch/r10b_launch.sh, launch/r10b_part.sh, launch/r10b_pnr.sh, launch/r10w_part.sh, ovf10.py, pdn_macro.tcl, srd.tcl
- `r11/` (13): abs.tcl, act_lef.py, blk_lib.py, fp11.py, ovf11.py, post_grt.tcl, probe_gpl.tcl, probe_place.tcl, propa.tcl, route_pre.tcl, run.sh, sta_paths.tcl, sta_rt.tcl
- `r12/` (10): ana12.sh, hm_probe.tcl, launch.sh, place_pre_drv.tcl, q1.py, q1dump.tcl, q2.py, q3.py, q3b.py, q3dump.tcl
- `r13/` (6): cell_dump.tcl, m2_short.py, postcts.sh, qb_act2_blk.f, qb_act2_blk_chip.f, run.sh
- `r14/` (9): abs14.py, drv_geo.py, drv_post.py, drv_sum.py, ovf14.py, probe_area.tcl, probe_drv.tcl, probe_path.tcl, run.sh
- `r15/` (4): drrun.sh, grtrun.sh, launch.sh, lay15.py
- `r17/` (2): lbp_feas.py, lbp_rowmap.py
- `r18/` (6): cls18.py, cuts.py, dump.tcl, geo.py, ovfmap.py, run.sh
- `r19/` (4): qb_act2_blk_chip_s1p.f, s1cut.py, s1cut_pi.py, stats.tcl
- `r20/` (5): pt_cls.tcl, pt_eco.tcl, pt_s1.tcl, s1tree.py, tgo_top.tcl
- `r21/` (8): budget.sh, chain.sh, clk_lat.tcl, cuts21.py, drlog.py, grt21.tcl, sta_cls.tcl, wv.tcl
- `r22/` (4): gate22.py, sq22.py, sq22.tcl, yband22.py
- `r23/` (8): aff23.py, aff23.tcl, aff23s.py, cord.py, mplace23.py, orun23.sh, pair23.py, pins23.py
- `r24/` (6): clk24.tcl, cls24.py, cls24.tcl, disp24.py, pc24_main.tcl, run24.sh
- `r25/` (5): an25.py, cls25.tcl, dr25.tcl, dump25.tcl, run.sh
- `r26/` (2): area26.tcl, rep26.py
- `r27/` (6): agg27.py, attr27.tcl, path27.tcl, pre27.tcl, run27.sh, stats27.tcl
- `r28/` (8): an28.py, ant28.sh, ant28.tcl, eco28.sh, eco28.tcl, hop28.py, mk28.tcl, pin28.tcl
- `r29/` (12): ant29.py, drc29.tcl, exp29.tcl, grtant29.tcl, net29.py, pdntest29.tcl, pg29.tcl, pt29.sh, pt29.tcl, pt29c.tcl, pt29d.tcl, sta29.tcl
- `r30/` (11): bin30.tcl, bins30.py, chain30.sh, dens30.tcl, dnt30.tcl, dr30.tcl, drc30.py, grt30.tcl, net30.tcl, pdn30.tcl, plc30.tcl
- `r31/` (7): clk31.tcl, cuts31.py, dchk31.tcl, gate31.sh, hold31.tcl, redo2.sh, seed31.sh
- `r32/` (7): chain32b.sh, cl32.tcl, m32.tcl, n32.tcl, pp32.sh, pp32.tcl, s32.tcl
- `r33/` (25): chain33.sh, ck33.tcl, coll33.tcl, cts33.tcl, dt33.py, gr33.tcl, h33.tcl, ins33.tcl, ob33.tcl, or33.sh, pl33.sh, pp33.sh, pp33.tcl, pp33b.sh, pp33b.tcl, pp33c.sh, pp33c.tcl, pp33d.sh, pp33d.tcl, pp33e.sh, pp33e.tcl, pr33.tcl, rp33.tcl, sb33.tcl, wl33.py
- `r34/` (7): idt34.sh, or34.sh, orq34.tcl, pg34t.tcl, pg34u.tcl, spt34.sh, spt34.tcl
- `r35/` (5): actlef.py, actlef.tcl, col_io.tcl, gpldiag.tcl, pc_setup_only.tcl
- `r36/` (12): absdb.tcl, abut.tcl, lefgeo.sh, mcgds.sh, pgdump.tcl, pgovl.py, pincmp.py, pinreach.tcl, probe_txt.py, probe_xy.py, rowmap.tcl, txtcount.py
- `r37/` (12): etmfix37.sh, hpost37.tcl, tau/r37_actfin.sh, tau/r37_acthold.sh, tau/r37_actpt_din74.sh, tau/r37_eco6.sh, tau/r37_hubeco.sh, tau/r37_hubeco1.sh, tau/r37_hubeco3.sh, tau/r37_hubeco4.sh, tau/r37_hubeco6.sh, tau/r37_hubfin.sh
- `r38/` (4): cellstat.py, dbexport.tcl, drc_req.sed, probe38.py
- `r39/` (5): bins39.tcl, drcbin.py, obsclash39.py, regrt39.tcl, wires39.tcl
- `r42/` (6): defwires.py, drcls.py, etmpins.py, obsdiff.py, pt42y.tcl, pt42z.tcl
- `r43/` (8): arr43.tcl, ema43.tcl, emaall43.py, hpath43.tcl, net43.tcl, pgbox43.tcl, rt43.tcl, wire43.tcl
- `r44/` (8): arm44.sh, fwd.tcl, icgbb.tcl, lat44.tcl, leaf44.tcl, pos.tcl, sh44.sh, trace.tcl
- `r45/` (24): act45.sh, chain45.sh, chain45b.sh, chain45c.sh, defat45.py, drcpin45.py, drcpos45.py, etmdiag45.tcl, etmnodrv45.tcl, etmout45.py, gdscell45.py, gen45.py, icgdrv45.tcl, icge45.py, lef57db45.tcl, lef57n45.py, pt45.sh, rr45.tcl, run45.sh, spefchk45.py, spefcov45.py, stack45.py, t45.cfg, techprobe45.tcl
- `r46/` (7): ant46.gdb, ant46.tcl, hold46.gdb, hold46.tcl, pin46.tcl, repro46.tcl, via46.tcl
- `impl/` top level (7): act2_summary.py, act_summary.py, core_summary.py, lane_batch.sh, lane_summary.py, pt_class.tcl, summarize.py
- `hard/` (14): col.cfg, col_geom.tcl, col_hb.tcl, col_pdn_macro.tcl, col_pins.tcl, col_place.tcl, col_post.sh, pe.cfg, pe_etm.tcl, pe_pins.tcl, pe_post.sh, pt_col.tcl, strip_blocks.py, topo_pe.tcl
- `hooks/` (4): mult_area.tcl, mult_booth.tcl, mult_nobooth.tcl, topo_strip.tcl
- `mem/` (9): mc_sweep.sh, mem_opt.py, s_nl.py, shapes.txt, shapes_all.txt, shapes_r3b.txt, shapes_rerun.txt, sweep_nl.txt, sweep_raw.txt
- `pnr/` (10): core.cfg, grt_est.tcl, io_place.tcl, pins.tcl, pt_diag.tcl, pt_post_core.tcl, slice_pins.tcl, slice_place.tcl, slice_repin.tcl, wire_share.py
