# TSMC 65 nm ASIC flow (Synopsys DC / PrimeTime / VCS)

A design-agnostic front-end flow: synthesis with Design Compiler, multi-corner static timing with PrimeTime and
RTL / gate-level simulation with VCS.  A design is given as a flat file list, a top module and a clock period.
The scripts contain no kit paths or cell names; those live in git-ignored site files.

```
flow/tsmc65/
  sync.sh            local <-> server link (git pull, pre-push rsync, remote run, fetch)
  site/              *.example.* templates (tracked); site.sh / site.csh / site.tcl real values (git-ignored)
  common/            lib.tcl (kit config, constraints, summaries), flist.tcl (file-list reader), tool.sh
  syn/               run_dc.sh + dc.tcl         DC synthesis
  sta/               run_pt.sh + pt.tcl         PrimeTime, one session per corner
  sim/               run_vcs.sh                 VCS RTL or zero-delay gate-level simulation
  smoke/             registered signed 8x8 MAC + self-checking testbench, run.sh runs the whole flow
```

## Site files

| template (tracked) | real file (ignored) | holds |
|---|---|---|
| `site.example.sh`  | `site.sh`  | ssh host (`QC_HOST`), ssh command, server checkout / work-tree dirs (read by `sync.sh`) |
| `site.example.csh` | `site.csh` | tool setup scripts, `QC_KIT`, `QC_CELL_V` (sourced by every tool run) |
| `site.example.tcl` | `site.tcl` | library dir, .db and operating condition per corner (ss / tt / ff), Milkyway + TLU+ for topographical mode, reference cells |

New site: `cp site.example.X site.X` for X in sh, csh, tcl and replace every `<PLACEHOLDER>`.  The real files are
never pushed; `sync.sh site` copies them to the server checkout (`sync.sh wip` copies them along).

## Running

All run scripts are executed on the server, from the repository root of a tree:

```sh
flow/tsmc65/syn/run_dc.sh  <design.f> <top> <period_ns> [tag]   # -> build/tsmc65/syn/<tag>/
flow/tsmc65/sta/run_pt.sh  <tag | syn_dir> [corner ...]          # default corners: QC_CORNERS (ss tt ff)
flow/tsmc65/sim/run_vcs.sh <tag> <tb_top> <a.f> [b.f ...]       # -> build/tsmc65/sim/<tag>/; QC_GLS=1 for netlists
```

Options are environment variables, documented in each script's header: `QC_CORNER`, `QC_TOPO=1`
(topographical mode), `QC_CLK`, `QC_SDC` (a design SDC instead of the generated single-clock constraints),
`QC_IO_PCT`, `QC_PARAMS`, `QC_HOOK` (Tcl sourced before compile), `QC_COMPILE`, `QC_CORES`, `QC_BUILD`.
Every run writes the full reports under `build/` (git-ignored, stays on the server) and a short `summary.txt` /
`pt_<corner>.txt` with area, gate count, setup / hold WNS / TNS and run time.

The home directory on the tau hosts is a small NFS quota (a smoke run already hit "Disk quota exceeded"), so put
builds on the host's local disk: `QC_BUILD=/tmp/$USER/qcnn/build`.  Such a build exists on that host only.

From the local machine:

```sh
flow/tsmc65/sync.sh pull                          # after git push: fast-forward the server checkout
QC_HOST=tau5 flow/tsmc65/sync.sh run 'flow/tsmc65/smoke/run.sh'
flow/tsmc65/sync.sh wip                           # before a push: rsync flow/ to the work tree ...
QC_TREE=wip flow/tsmc65/sync.sh run '...'         # ... and run there
flow/tsmc65/sync.sh fetch build/tsmc65/syn/<tag>/summary.txt
```

## File lists

`common/flist.tcl` reads the flat format of `bender script flist` (and VCS `-f` files): one source file per
token, `+incdir+<dir>`, `+define+<NAME>[=<VAL>]`, nested `-f` / `-F`, `//` and `#` comments, `$VAR` expansion.
Relative paths are relative to the `.f` file.  DC analyzes every non-VHDL file as SystemVerilog with the
collected defines (plus `SYNTHESIS`) and incdirs; VCS gets the same list flattened (`tclsh common/flist.tcl a.f`).
For a bender project: `bender script flist -t synthesis -t asic > design.f` (absolute paths).

## Smoke test

`flow/tsmc65/smoke/run.sh [period_ns=2.5]`: DC (wire-load and topographical), PrimeTime at ss / tt / ff, VCS
RTL simulation and zero-delay gate-level simulation of the DC netlist.  It shows that the tools start, the
licences check out and the kit paths are right.

## Not covered (yet)

Place and route, SRAM macros, power with switching activity, formal equivalence.  Notes for later: ICC2
(`/CMC/scripts/synopsys.icc2.*`), Fusion Compiler and Cadence Innovus (`cadence.innovus*`, up to 21.17) setup
scripts exist on the tau hosts; the standard-cell kit has LEF (6-9 metal layers) and Milkyway views.  The ARM
memory compilers (single-port SRAM, single- / two-port register file, ROM) are under
`/CMC/kits/arm_tsmc65gp-nonCmcPsa/aci`; they give front-end views only (liberty, Verilog, footprint; no GDS) and
need host workarounds (system Java 8, a copy on a local file system) - see the SGWA project's `flow/tsmc65/sram`.
