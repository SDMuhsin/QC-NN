# qc18bacc implementation flow

Stage-organized implementation flow of the qc18bacc chip on TSMC 65 nm: DC synthesis, IC Compiler II P&R through the
shared hard-block driver `common/block.sh`, PrimeTime, Calibre.  Blocks on the driver: the column `blocks/col` and the
regression block `blocks/rgr`; the act / hub / top blocks are to be ported onto it (see "Removed OpenROAD-era flow").

## Layout

| dir | contents |
|---|---|
| `common/` | `env.sh` (bash: `QBF`, `ROOT`, `B`, `TOOLS`, `PY`, `qb_kit`, `qb_pt`, `qb_icc2`, `qb_corners`), `block.sh` (shared ICC2 hard-block driver), `block_sdc.tcl` (netlist + P&R SDC of a hard block from its DC run), `act_chain.tcl` (the act chain contract of the act source and the column budgets, R107), `constraints.sdc` (DC / PT SDC), `limits.tcl` / `limits.txt` (sign-off limits), `derate.tcl`, `lib_cells.tcl` / `lib_tcq.py`, `eco_changes.tcl`, `queue.sh` (detached step queue per host), `status.sh` (run status digest), `deploy.sh` (immutable flow snapshot of one commit on a build host), `regress.sh` (the flow regression) |
| `synth/` | DC / top-netlist steps that produce the P&R input netlists |
| `floorplan/` | `pg_grid.tcl` (chip PG strap grid), `abstract_pins.py` / `edge_pins.py` (floorplan pin DEF / pin-only abstract) |
| `icc2/` | IC Compiler II steps (R54): `common.tcl` (kit + block config, `qb_open` / `qb_done` / `qb_qor`), `libs.tcl` (std-cell NDM, icc2_lm_shell), `init.tcl` (design library, TLU+, netlist, MCMM, SDC), `floorplan.tcl`, `place.tcl`, `cts.tcl`, `route.tcl` (`qb_route_setup` / `qb_fillers` / `qb_route_close` in common.tcl), `eco.tcl` (R56: sources the PrimeTime change list, legalise, route_eco, refill), `outputs.tcl` (label `QB_ICC2_LABEL`), `extract.tcl` (R68: Calibre fill read back as DEF FILLS, fill-aware SPEF per sign-off corner), `abstract.tcl` (abstract LEF + port antenna data + abutment check for the top); block facts in `blocks/<b>/icc2.cfg` |
| `signoff/` | `pt/` PrimeTime (block sign-off `blk.tcl`, DMSA ECO `drv_eco.tcl`); `etm/` ETMs (`etm.tcl`, `etmcheck.py`; `arc_except.txt`: the pins that need not have the setup / hold or clock -> out arcs of their direction, each with its reason, R111); `calibre/` fill, LVS source (`v2lvs_allow.txt`: the v2lvs warnings that may pass, R109), Calibre DRC / LVS (+ its ERC; `erc_allow.txt`: the ERC checks that may be NOT EXECUTED) / antenna (`drc_allow.txt`: the DRC / antenna rule checks that must be the NOT EXECUTED ones; every deck sed file states its results as `#@expect` / `#@absent` lines, cal.sh cal_deck, R109; R111: deck edits are `-f <sed file>` pairs only, an LVS add-on QB36_LVS_EXTRA has its own `#@expect` lines); `portcheck.py`; `verdict.sh` the machine verdict of a block run |
| `blocks/<b>/` | per block on the driver: `<b>.env` (parameters), `icc2.cfg` (ICC2 block config), `io_budget.tcl`, `run.sh` (steps); `blocks/act/io_budget.tcl` is the act DC's IO budget (synth/run.sh act) |

Every block is run from a host-local copy of the repository on the build server
(`QC_BUILD` default `/tmp/$USER/qc18bacc/build`, tools in `QC_TOOLS` default `/tmp/$USER/tools`, kit paths in the
untracked `flow/tsmc65/site/*` files). P&R runs land in `$QC_BUILD/icc2/<blk>/<tag>` (`run.sh rundir <tag>`).

Unattended runs (R50): `common/queue.sh <logdir> <spec>` runs `blocks/<b>/run.sh` steps one after the other in a
detached session (setsid + nohup; kill the queue with `kill -- -<pgid>`), one spec line per step
`<wait> [VAR=val ...] <blk> <step> <run> [args]` (`<wait>`: `-` or `pid:N`, `file:PATH`, `grep:PATH:PAT`,
`need:PATH:PAT`, comma-separated); it stops at the first failure and keeps `<logdir>/queue.state` (n blk step run
status start end rc) and `q<n>_<blk>_<step>.out`.  One queue per host keeps one heavy job per host (30 GB).
`common/status.sh <run_dir|blk/tag>...` prints at most 15 lines per run: current step + elapsed, PT setup / hold / DRV
per corner, last ERROR line, last ECO round and route gate, queue.state of the run.

Exit status (R53): `synth/run.sh` (flow/tsmc65 `run_dc.sh` / `run_pt.sh`), every step of
`blocks/*/run.sh` and `signoff/calibre/*.sh` exit non-zero when a tool or a gate fails (PrimeTime: `common/env.sh qb_pt`;
ICC2: `qb_icc2`; background jobs: `qb_wait`), so a queue stops at that step.

## Column block qb_col_blk (`blocks/col`, ICC2 since R54, results/r54.md)

```
qc18bacc/flow/blocks/col/run.sh pnr <tag>       # ICC2 libs init floorplan place cts route outputs + fill -> $QC_BUILD/icc2/col/<tag>
qc18bacc/flow/blocks/col/run.sh fill <tag>      # (portcheck +) Calibre dummy metal of the outputs GDS -> DEF FILLS (signoff/calibre/fill_def.py) -> fill-aware ICC2 SPEFs (icc2/extract.tcl), every sign-off corner; kit dummy OD / PO (cal.sh odpo, odpo_blk.sed, R77); both fills in the chip window = DEF DIEAREA (R99)
qc18bacc/flow/blocks/col/run.sh eco <tag>       # the sign-off ECO loop (common/block.sh): per round one PT DMSA ECO in every sign-off corner (signoff/pt/drv_eco.tcl: DRV, setup, hold, noise) applied by ICC2 eco.tcl, outputs + fill of its label (eco, eco2, ...)
qc18bacc/flow/blocks/col/run.sh post <tag>      # PT in every sign-off corner at 6.5 ns on the ICC2 netlist + fill-aware SPEF (gzip), ETMs of every sign-off corner
qc18bacc/flow/blocks/col/run.sh views <tag>     # ICC2 abstract LEF with port antenna data + antenna / abutment / PG pin gates (out/qb_col_blk.lef), etmcheck (for the chip top)
qc18bacc/flow/blocks/col/run.sh calibre <tag>   # LVS source, Calibre LVS / DRC (block deck + OD.DN.1 / PO.DN.1) / antenna on the metal + OD / PO filled GDS of the fill step -> <run>/calibre
```
The label of out/ (R96, common/block.sh blk_out): `out/label.txt` names the ICC2 label whose outputs, portcheck, fill and
SPEFs out/ holds, written only once all of them passed; an unfinished label (`out/label.new`) is finished by the next fill
or eco step, and post / calibre / views / the verdict refuse a run without a complete label.  A pnr step init .. route
drops the label of out/ (R99: a partial re-run would leave out/ of the old layout under a label) and moves its ECO
history out/eco aside to out/eco.pnr_<date_time> (R106), and so does a pnr range from outputs, which first requires the
route step's log to pass (`qb_icc2 -check`, R111) and route to have completed after init .. cts (R113, "Sign-off scope"); the verdict checks the log of every ICC2 step of the label chain of
out/ (gate icc2_log: init .. route, each ECO round's out/eco/<label>/eco.log, outputs / extract of the label, abstract;
R111) and the legality of every ECO label after place_eco_cells and after its refill (R111); views makes the abstract
of the label of out/ only (an inherited QB_ICC2_LABEL naming another label fails) and abstract.tcl records it, which the
verdict's abstract_label gate compares with out/label.txt.  The floorplan pin DEF is the run's own `<run>/pins.def`
(QB_PIN_DEF, written by the block's blk_pre_pnr before each floorplan step; R99, was one file per host).
Sign-off limits (R99): `common/limits.txt` is the one committed value of QC_UNC_SETUP / QC_UNC_HOLD / QC_IO_PCT /
QC_MAX_TRAN / QC_MAX_TRAN_PCT / QC_CLK_TRAN_MAX / QB5_SOUTH_IN and the act chain's QC_ACT_HOLD_HUB / QB_ACT_LAUNCH (R107, both ends: `common/act_chain.tcl`) (`common/limits.tcl` qb_limit: DC / PT SDC, P&R SDC
(R103, common/block_sdc.tcl), IO budget, PT clock limit, ICC2 CTS, ICC2 setup uncertainty (R103, icc2/init.tcl qb_sdc)); an
environment value overrides it for an experiment, PrimeTime logs the values in force (QB_PT_LIMITS) and the verdict's
limits gate fails every corner where they differ from limits.txt.  DC's run.env is not read by the block PrimeTime
(R100, common/block.sh blk_pt_env: its QC_IO_PCT acted as such an override); since R107 it records the limits DC used
and every knob a DC hook declares (flow/tsmc65 `common/knobs.tcl`), and QC_IO_PCT only without a design SDC; since R115
also how the netlist was made (QC_CORNER, QC_FLIST, QC_PARAMS, QC_HOOK, QC_POST_HOOK, QC_COMPILE), and `synth/run.sh
col|rgr` set the corner of their output name (tt) and fail on an environment QC_CORNER that differs.  ECO history
(R115): a round counts (lifts a stop, gives the previous total) only by its "applied" line, written once its ICC2 eco
and the outputs / fill of its label passed (common/block.sh blk_eco_applied).
Corners (R68): one table, `flow/tsmc65/site/site.tcl` QC_SIGNOFF (kit release note RN_TCBN65GPLUS_140B NOTE I): setup
{wc wcl} x {Cworst RCworst} (ss ss_rcw wcl wcl_rcw), hold {lt ml} x {Cbest RCbest} (ff ff_rcb ml ml_rcb), tc typical (tt);
ICC2 MCMM, PT sign-off, the DMSA ECO, the block ETMs and the chip top use all of them (bash: common/env.sh `qb_corners`;
R71), DC the base corners QC_CORNERS {ss tt ff}.  Feedthroughs act -> act_o: one fixed lib
cell (blocks/col/io_budget.tcl QB5_FT), dont_touch with their act_o nets (icc2/init.tcl, PT col_blk.tcl); act[b] input
transition = the block's own measured act_o[b] transition per corner (io_budget.tcl qb5_io_tran*, R71).  Abstract: M1 ..
M7 blocked over the die except the pins (icc2/abstract.tcl, R71; made on its own block label "abstract", R77).  Routing:
redundant vias after every detail route (R71), route setup also before CTS (R77).  Lib cells (R77, common/lib_cells.tcl):
clock-tree cells by exact family minus QC_DONT_USE, a dont_use gate in every ICC2 step / DMSA scenario / PT corner, and the
library's fastest clock -> Q (common/lib_tcq.py) as the period-independent min input delay (io_budget.tcl); IO latency
late / early per check (PT signoff/pt/io_lat.tcl, ICC2 compute_clock_latency).  Database unit = tech file 1000 / um (R77).
Inputs: netlist + SDC `$B/syn/qb_col_blk_r5d_s20_tt_p1.65_topo` (P&R SDC: common/block_sdc.tcl + blocks/col/io_budget.tcl
at 5.0 ns), pin positions of the reference abstract `$B/r5b_blk/qb_col_blk_ring.lef` (the ones r48 placed; its md5 in the run's
`init inputs` line, R101), written as the
floorplan DEF `<run>/pins.def` by floorplan/abstract_pins.py in the pnr step (R72). Parameters: `col.env`, `icc2.cfg`.

## Sign-off scope

The block sign-off is the machine verdict `signoff/verdict.sh` (run.sh signoff): PrimeTime timing / DRV / noise in every
sign-off corner, the ICC2 step logs and P&R gates, Calibre LVS (+ ERC), DRC and antenna, ETMs and the abstract.  Provenance
(R113): every ICC2 step that passes appends `icc2_done <step> <label> <epoch>` to summary.txt (common/env.sh qb_icc2), and
the verdict's step_order gate requires the label chain of out/ to have completed in order (init < floorplan < place < cts
< route < ECO rounds < outputs < extract, and outputs < abstract (R114); summary.txt line order, not file times), as does a pnr range from outputs for
init .. route; each consumer step records the md5 of the files it read and wrote (`chain` lines, common/block.sh
blk_chain: fill, extract, PT and ETM per corner, LVS / DRC / antenna, and (R114) the abstract: DEF of the label -> LEF,
after views checked out/ against the label's `outputs_md5` line, blk_out_check), and the verdict's md5_<step> gates hold them
against the files as they are (views: the ETMs of the label of out/).  `outputs_md5` covers the netlist, DEF and PG
netlist (R114) and the GDS (R115, common/gds_md5.py: without its time stamps; the fill step checks out/ against it
first); the verdict's lvs_source_netlist holds out/ against it.  R115: a chain line is written only when its step
passed (post: PT / ETM), calibre reads the filled GDS of the fill record (no file times), every step appends its
BLK_KNOBS line to summary.txt and the verdict's flow_snapshot gate requires one flow root (its own) for all of them,
and the Calibre gates require Calibre's exit status 0.  The file-time fresh_* gates stay as a second check
of the links no step records; a run dir copied without its times can only fail them.
Out of scope by the project owner's decision: formal equivalence checking (LEC / Formality) of the P&R netlist against
the synthesis netlist; the CAS papers the chip is compared with do not report it.  The netlist checks the flow does make
are the port gate (signoff/portcheck.py), the ECO change-list gates (icc2/common.tcl qb_eco_names) and LVS against the
P&R netlist.  Also out of scope (paper-only): fabrication, IR drop / EM sign-off (no licence; a labelled PG estimate only).

## Regression block qb_lane_n (`blocks/rgr`) and flow snapshots (`common/deploy.sh`)

Every flow change passes the regression block before it may run on the column, through its one entry point
`common/regress.sh` (local checkout; ssh command QC_SSH, as deploy.sh):
```
qc18bacc/flow/common/regress.sh run <commit> <host>     # deploy.sh -> /tmp/<user>/qc18bacc/rgr_<run>, the chain detached (queue.sh)
qc18bacc/flow/common/regress.sh check <host> <run> [<commit>]  # exit 0 only on: run of <commit> (default HEAD), chain complete, SIGNOFF PASS, gate set = reference
qc18bacc/flow/common/regress.sh ref <host> <run> [<commit>]    # (re)writes blocks/rgr/reference.txt from a passing run of <commit>
```
`run` names the run rg<7 hex digits of the commit><first free letter> and launches pnr eco calibre post views signoff from
the snapshot (queue log dir <run dir>q); the block's configuration alone decides the run, no VAR=val on the queue line.
`check` first ties the run to the flow under test (R99): the tree in the snapshot's VERSION must have the
qc18bacc/flow and flow/tsmc65 of `<commit>` (or tree; default HEAD) apart from reference.txt, and (R104) the snapshot's
files must still match its MANIFEST.md5 on the host (md5sum -c, no unlisted file); the reference compared with is
`<commit>`'s own blocks/rgr/reference.txt (git show), not the checkout's; then it reads the run's queue.state (exactly that chain, every step ok, rc 0),
the settings (R103): every step's `BLK_KNOBS` line (common/block.sh blk_knobs: the flow root the step ran from and
every flow knob in force, common/env.sh qb_knobs: P&R guard-bands, ECO margins / rounds / modes, pnr range, cores, ICC2
binary / label, LVS deck extras, the Calibre deck edits of every mode BLK_*_SED (R104: ant has its own, BLK_ANT_SED), the sign-off limits) must name the snapshot and equal the snapshot's committed defaults
(`run.sh knobs` in an empty environment), which equal the reference's `knobs` line, and the queue spec has no VAR=val
word; and its signoff step's verdict, which the snapshot's signoff
step re-run on the run dir must reproduce line for line (R102, check verdict_rerun)
(SIGNOFF PASS, no FAIL / MISSING gate, VERDICT line = the reference's) and compares its gate set (gate name x corner) with
`blocks/rgr/reference.txt`, printing the difference: a checker that adds, drops or renames a gate fails the regression
until the reference is rewritten with `ref` and the change is reviewed in the commit.  Repeatability (R109 [M],
icc2/common.tcl): ICC2 on several cores is not run-to-run repeatable, two rgr runs of one tree, knobs and inputs differ
from place_opt's global route on, also with every ICC2 repeatability option set (place_opt / refine_opt / clock_opt
`.flow.repeatability`, `route.global.deterministic`); 1-core runs are identical (two hosts) at about twice the ICC2 wall
time.  So the block runs ICC2 on 1 core (R110, PI decision: `rgr.env` QB_ICC2_CORES=1, sourced before common/env.sh's
default 16; an environment value fails the knobs check), and `check` also compares the route label's netlist / DEF md5
(summary.txt `outputs_md5 route`, common/block.sh blk_out_md5: without the writers' comment lines) with the reference's
`route_md5` line, which `ref` writes from a 1-core run.  common/queue.sh does not source env.sh (R110): a step's
environment is the queue's plus its VAR=val words.  By hand, the chain is:
```
qc18bacc/flow/common/deploy.sh <commit> <host>:<dir>    # git archive of qc18bacc/flow + flow/tsmc65 at <commit> + the host's untracked site files -> <dir>
qc18bacc/flow/synth/run.sh rgr                          # once per build root: DC of one PPU lane -> $B/syn/rgr_lane_tt_p2.0_topo
<dir>/qc18bacc/flow/blocks/rgr/run.sh pnr <tag>         # the column's pnr (libs .. outputs, portcheck, fill) -> $B/icc2/rgr/<tag>
<dir>/qc18bacc/flow/blocks/rgr/run.sh <eco|calibre|post|views|signoff> <tag>   # the rest of the chain, in this order
```
deploy.sh archives a commit (or tree) id, never the working tree: every tracked file of qc18bacc/flow and flow/tsmc65
(`deploy.sh --paths`); from the host only the untracked kit-derived site files of flow/tsmc65/site (R100: before, the
host's whole flow/ including tracked lib.tcl / tool.sh).  It writes VERSION (commit, tree, site source, the site manifest
= one `site_md5 <md5> <path>` line per site file, deploy time) and MANIFEST.md5 (every other file), verifies both on the
host, makes the snapshot read-only and refuses an existing <dir>.  The site manifest also has (R115) one `kit_md5 <role>
<md5>` line per kit file the flow reads by path, keyed by role (common/env.sh qb_kit_files, the one role table: tech file,
cell LEF / GDS, TLU+ per corner and map, timing .db and liberty per corner, Calibre decks, LVS cell spice; the paths are
resolved on the host only, so neither VERSION nor the reference names a kit file), and `check` re-checks every manifest
line on the host (site_now).  `check` also compares the site manifest and the run's
inputs from outside the snapshot (summary.txt `init inputs`: md5 of netlist, DC SDC, run.env, then the block's own
`BLK_INPUTS`, e.g. the column's reference abstract (R101), the regression block's DC database (R109); written by common/block.sh blk_inputs after each successful init step (R109; init.tcl refuses an existing design library); every later reader, the portcheck and the floorplan pin
DEF, gets the file through blk_input, which fails unless its md5 is still the recorded one, R102)
with the reference (R100): a new site file or a re-synthesised netlist needs a reviewed `ref`.  The block uses the shared driver like the column: `rgr.env` (netlist tag, period 2.5 ns, die 130 x 130 um, pins,
the column's P&R guard-bands QC_PNR_GUARD_HOLD 0.010 ns / QC_PNR_GUARD_TRAN 0.05, as `col.env`, ICC2 cores 1; environment overrides them),
`icc2.cfg` (the column's opt-ins HOLD_RESERVE / ISOLATE / VIRTUAL_FILL / PREROUTE_CAP_SCALE / PREROUTE_SETUP_MARGIN and, R109, its per-bit chain IO IO_LOAD / IO_TRAN, y_o -> x, on this design), `io_budget.tcl` (the column's budget procs with
its own class table `::QB5_BUDGET`), pins: `floorplan/edge_pins.py` (pin-only abstract LEF: inputs west, outputs east on
M3 tracks) -> `floorplan/abstract_pins.py` (floorplan DEF).  Block-config hooks of the shared ICC2 steps: `P(IO_SAMPLE)`
(init's logged IO delays) and `P(IO_PAIR)` (qb_io_lat's port-to-port clock delays; the column: act[0] -> act_o[0]).
Every step of the driver runs on it (step 2): `eco`, `calibre`, `post`, `views`, `signoff` as the column's.  PrimeTime:
`signoff/pt/blk.tcl` is the one block sign-off (setup, report, gates, noise); a block's BLK_PT sets its IO budget and
hooks (`qb_blk_hook`: design setup, path classes, extra lines / reports / noise gates) and sources it:
`signoff/pt/col_blk.tcl` (the act feedthrough: QB5_FT dont_touch, act_o load, act input transition, act noise state,
act_noise gate), `signoff/pt/rgr_blk.tcl` (input -> reg, reg -> output; noise on the SDC's input driving cells).
Column-only gates are opt-in: icc2/abstract.tcl abutment with `P(ABUT_PAIR)` (blocks/col/icc2.cfg), signoff/verdict.sh
`-g` from the block's `BLK_GATES` (the column: act_noise, abstract_abutment; checked also whenever a run has their evidence).

## Inputs: netlists, top netlist (`synth/`)

```
qc18bacc/flow/synth/run.sh col              # column DC -> syn/qb_col_blk_r5d_s20_tt_p1.65_topo
qc18bacc/flow/synth/run.sh act [r35_act]    # act DC (S1T) -> syn/r35_act
qc18bacc/flow/synth/run.sh chip <tag>       # chip DC -> syn/r26_ptr (hub partition source), syn/r35_ptr (top)
qc18bacc/flow/synth/run.sh topnl r35_w      # top netlist -> $B/r35/top_r35.v (+ bpins / equiv / actmap) from the frozen partition $B/r35_w
qc18bacc/flow/synth/run.sh actpins          # $B/r35/col_act_pins.txt (act pins aligned to the column abstract)
qc18bacc/flow/synth/run.sh macros           # ARM SRAM views
```
These steps were moved path-only from their rounds in R47 (not re-run then). Not
recorded at the time and reconstructed from logs: the act DC (`$B/r35_actsyn.out`), the r35_ptr chip DC (`$B/r35_syn.out`),
`col_act_pins.txt`. Frozen artifacts with no producer in this flow: `$B/r5d_Ctiles` (PE tiles of the R5d column run) and
`$B/r5b_blk` (reference column abstract + ETMs of R5b; `git show c9ea93f:qc18bacc/impl/r5b/run.sh` blk step), the hub
`r37_ssx*_ports.txt` port lists (R37, partly hand-edited), the hub partitions `$B/r26_w` / `$B/r35_w` (removed `part` step).

## Removed OpenROAD-era flow

The OpenROAD P&R flow of the act / hub / top blocks (`blocks/{act,hub,top}` but `blocks/act/io_budget.tcl`,
`floorplan/` pins / PDN / macro placement, `place/`, `cts/`, `route/`, `repair/`, `common/or.sh` / `qb.tcl` /
`lib_pincap.py`, `signoff/spef.sh` / `antenna.tcl` / `drc_hist.py` / `hub_check_ant.tcl`, the OpenROAD-only PT / ETM /
Calibre scripts, the one-corner DRV ECO mode of `signoff/pt/drv_eco.tcl`, the hub partition step `synth/run.sh part` =
`synth/partition.sh` + `part_*`, which read the netlist with OpenROAD), the R47 equivalence proof and the old
`impl/` -> `flow/` file map were removed (OpenROAD is not run again; P&R is ICC2).  The last commit that has them is
1ea4f5e: `git show 1ea4f5e:qc18bacc/flow/<path>`, e.g. `blocks/hub/run.sh` or this README.  The act / hub / top blocks
are to be ported anew onto `common/block.sh`, as `blocks/col` and `blocks/rgr` are; the hub partitioning is to be
re-implemented with ICC2 / DC / PrimeTime netlist reading in the chip-level port.
