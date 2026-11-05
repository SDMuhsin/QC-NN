# Place and route with OpenROAD (TSMC 65 nm)

Commercial P&R is not usable on the tau hosts (the Cadence licence server refuses the account; ICC2 and Fusion
Compiler are not installed), so this stage runs OpenROAD against the CMC tcbn65gplus kit.  It takes a DC netlist
and SDC (`syn/run_dc.sh`) and produces DEF, a routed netlist, SPEF per corner and, optionally, a GDS merged with
the cell GDS.  All kit-derived files (router LEF copy, RC tables, layer map, GDS) stay in the build directory on
the server; only scripts and summary text belong in git.

```
pnr/
  install_openroad.sh   OpenROAD + KLayout via micromamba into /tmp/$USER/tools (no root, not the NFS home)
  run_pnr.sh            driver: OpenROAD flow -> def2spef per corner -> OpenROAD post-route STA -> GDS merge
  run_pt_post.sh        PrimeTime post-route check with the SPEF (pt_post.tcl)
  smoke.sh              DC + P&R + PrimeTime of the smoke MAC
  designs/*.cfg         per-design settings (Tcl, set P(KEY) value)
  or/                   OpenROAD Tcl: flow.tcl, lib.tcl (defaults, helpers), one file per step
  py/                   captable_rc.py, def2spef.py, lef_pnr.py, gds_map.py, gds_merge.py (KLayout)
  test/                 synthetic macro (LEF + lib, not a kit view) for the macro hook, designs/macro_test.cfg
```

## Setup

1. On the server: `flow/tsmc65/pnr/install_openroad.sh` (about 3 min, 4 GB in `/tmp/$USER/tools`, host-local, so
   it must be run on each host).  OpenROAD comes from the litex-hub conda channel (Feb 2024 build
   2.0-12381; it needs `pkgs/main` for its boost, plain conda-forge only resolves a 2022 build), KLayout from
   conda-forge in a separate env.  Release .deb packages need glibc 2.31+, and RHEL 8 has 2.28.
2. Kit settings: `cp site/pnr.example.tcl site/pnr.tcl` and fill in the placeholders (tech LEF, captables per corner,
   cell GDS, Virtuoso layer map, cell names, layers).  It is read after `site.tcl`, so the liberty files are the ones
   DC uses (`QC_LIBDIR` / `QC_LIB(corner)` with `.lib`).

## Running

From the repository root of a server tree, with `QC_BUILD=/tmp/$USER/qcnn/build` (see the flow README):

```sh
flow/tsmc65/pnr/run_pnr.sh flow/tsmc65/pnr/designs/<design>.cfg [tag]   # -> $QC_BUILD/pnr/<tag>/
flow/tsmc65/pnr/run_pt_post.sh <tag> [corner ...]                       # PrimeTime with the routed SPEF
flow/tsmc65/pnr/smoke.sh                                                # whole smoke test
```

Environment: `QC_PNR_SYN` (synthesis tag or dir instead of `P(SYN)`), `QC_PNR_SET` (Tcl list `{KEY VALUE ...}` that
overrides the config), `QC_PNR_FROM` / `QC_PNR_TO` (step range; a run restarts from the checkpoint of the step
before `QC_PNR_FROM`), `QC_PNR_POST=0` (skip SPEF, post-route STA and GDS), `QC_PNR_THREADS` (8), `QC_TOOLS`.

Steps (`or/<step>.tcl`, each ends in `db/<step>.odb` + `.sdc`):

| step | does |
|---|---|
| init | liberty of every corner (`define_corners`), router LEF + macro LEFs, netlist, SDC, per-corner RC |
| floorplan | die / core from `CORE_UTIL`, `ASPECT`, `CORE_MARGIN` (or `DIE_AREA` + `CORE_AREA`), tracks, macros, tie cells for driverless constant nets, optional tapcells, IO pins |
| pdn | M1 followpin rails + `PDN_V_*` / `PDN_H_*` straps, macro grid, `check_power_grid` |
| place | global placement (timing + routability driven), tie fanout, `repair_design` of the nets with DRV violations only (`REPAIR_DESIGN auto`; `1` = plain `repair_design`), detailed placement |
| cts | `clock_tree_synthesis` with the site clock buffers, propagated clocks, setup then hold repair |
| route | global route, antenna repair (diode `ANTENNA`), decap + filler cells, detailed route, `check_antennas` |
| finish | DEF, netlist without fillers (`<top>.v`, for STA) and with PG + fillers (`<top>_pg.v`), pin dump for def2spef |

After the flow, `run_pnr.sh` writes `out/<top>_<corner>.spef` (and `_pt.spef`, see below), re-times the routed
design in OpenROAD with these SPEFs (`post_route_<corner>` lines) and merges the GDS.  `summary.txt` has one line
per step (utilisation, WNS / TNS per corner), PDN connectivity, DRC and antenna counts and run time; full reports
are in `rpt/` (`drt.drc.rpt` is the detailed-route violation list).

### Design config

`designs/smoke_mac8.cfg` is the minimal example.  Keys and defaults are in `or/lib.tcl` (`P_DEFAULT`):
`TOP`, `SYN` or `NETLIST` + `SDC`, floorplan (`CORE_UTIL`, `ASPECT`, `CORE_MARGIN`, `DIE_AREA`, `CORE_AREA`),
`PLACE_DENSITY` (default util + 0.2), PDN strap layer / width / pitch / offset, CTS clustering (+ `CTS_ARGS`, extra clock_tree_synthesis options), repair margins,
`GR_ADJUST`, `DR_END_ITER`, `DR_ARGS`, `FILL`, `DCAP`, `GDS`, and Tcl hooks `FLOORPLAN_TCL`, `PIN_TCL`, `PDN_TCL`,
`PRE_PLACE_TCL`, `PRE_CTS_TCL`, `PRE_ROUTE_TCL`, `POST_ROUTE_TCL`.

Macros (SRAMs with LEF + lib, no GDS): `MACRO_LEFS`, `MACRO_LIBS_ss` / `_tt` / `_ff`, `MACRO_PLACE`
(`{{inst x_um y_um orient} ...}`, fixed), `MACRO_AUTO` (place the others with `macro_placement`), `MACRO_HALO`,
`MACRO_PIN_LAYER` (PG pin layer, connected to the `PDN_H_LAYER` straps) or `MACRO_PDN_TCL`, `MACRO_GDS`.  The GDS
merge keeps the LEF abstract of a macro without GDS and lists it as `no GDS`.  For PrimeTime, pass the macro .db
files in `QC_EXTRA_DB_SS` / `_TT` / `_FF`.  `designs/macro_test.cfg` checks the hook with a synthetic block.

## Approximations and known gaps

* **Parasitics.**  The kit has no QRC deck and OpenRCX has no rules for it, so RC comes from the captables
  (`py/captable_rc.py`; `ss` uses cworst, `tt` typical, `ff` cbest, as the TLU+ files in DC).  Each layer gets one R
  and one C per um, for a minimum-width wire at minimum pitch with neighbours on both sides:
  C = `Ctot` of the BASIC_CAP_TABLE (wire over substrate, interpolated in spacing), R = `Rho` /
  (thickness x mean of top and bottom width); via R per cut from the captable.  Wires between metal above and below
  have more area cap; wires at relaxed spacing have less coupling.  There is no coupling cap (all to ground, no SI)
  and no temperature dependence.  These values feed `set_layer_rc` (and `set_wire_rc` for pre-route estimates).
* **SPEF.**  `py/def2spef.py` turns the routed DEF into a distributed RC network with these per-layer values (segment
  R, half the segment C at each end, via R / cuts, pins attached to the nearest wire node).  It is a geometric
  estimate, not a field-solver extraction, so read post-route timing as indicative.
  `<top>_<corner>.spef` keeps `/` in flat names unescaped (OpenROAD), `<top>_<corner>_pt.spef` escapes it (PrimeTime
  reads the flat routed netlist, where `u_a/reg` is one instance name).
* **Minimum cut on M1.**  Most tcbn65gplus output pins are M1 shapes >= 0.3 um wide, and the LEF requires two VIA1
  cuts on such metal (`MINIMUMCUT 2 WIDTH 0.300`).  The detailed router's pin access only uses single-cut vias and
  reports "no access point" (DRT-0073).  The router therefore reads a copy of the LEF without the M1 MINIMUMCUT rules
  (`QC_PNR_LEF_NO_MINCUT`, `py/lef_pnr.py`).  Single-cut VIA1 on wide pins will show up in a sign-off DRC (Calibre);
  the router's 0-violation count does not cover them.
* **Unsupported LEF rules.**  OpenROAD ignores the `LEF57_SPACING` end-of-line and `LEF57_MINSTEP` properties
  (ODB-0388), so those rules are not checked either.  No metal density fill is done.
* **Utilisation.**  `repair_design` resizes cells towards a target slew once it runs: in the smoke run, 153
  cells and +41 % cell area for the 0.25 ns `max_transition` at ss.  Leave room for this in `CORE_UTIL`.
* **Input netlist: synthesize with wire load.**  Audit on one Snitch FPU (94k cells, 4.0 ns at ss, netlist from a
  zero-wire-load DC run, see the flow README "Wire-load model"): OpenROAD init +0.29 ns, after global placement
  -4.07 ns with 24k slew-violating pins (D0 / D1 drivers on real wires); plain `repair_design` resized 80k of the
  94k instances (+84 % area) and only reached -1.6 ns (-3.96 ns at global route after CTS and `repair_timing`,
  +93 % area); repairing only the violating nets keeps the area (+12 %) but leaves -3.2 ns.  DC topographical on the
  same netlist closes 4.0 ns with +8 % area, the kit WLM (`WireAreaLowkCon`) gets -0.23 ns with +9 %.  The RC
  itself was checked and is not the cause: per-um R / C as set (1.09 Ohm, 0.266 fF on M2-M7 at ss cworst; 1.40 /
  0.222 at tt) arrive unchanged in OpenROAD (kOhm / pF per um = liberty units), a 500 um net gets 0.134 pF and a
  37.8 ps wire delay (Elmore by hand 36.5 ps), the def2spef SPEF reads with the same caps in PrimeTime, and PT and
  OpenROAD agree within 1 % on a long-wire chain (same liberty, slew thresholds / derate handled alike).
* **repair_design resizes every driver.**  Even on the DC topographical netlist of that FPU (0.00 ns, 247k um2),
  plain `repair_design` resized 75k of 96k instances for ~600 violating nets and the placement no longer fit at
  50 % utilisation.  `REPAIR_DESIGN auto` therefore runs it with all non-violating signal nets dont_touch
  (`qc_repair_drv` in `or/lib.tcl`): +7 % area after placement, +11 % after CTS / hold repair, ss WNS -1.80 ns
  (placement), -0.94 ns (CTS + `repair_timing`), -1.44 ns at global-route RC, with `TIMING_DRIVEN 0`.
