# R5c: structured PE placement, flat routing, for the column block `qb_col_blk`

Labels as `results/r5a.md`: **[S]** static (DC / P&R geometry, PrimeTime with the def2spef SPEF, or OpenROAD's own
estimate where marked [OR est.]); **[M]** simulation; **[R]** reasoning from [S] numbers.  Tools as R5a (OpenROAD
2.0-12381, PrimeTime Q-2019.12, VCS S-2021.09).  Hosts tau6 (run A) and tau3 (run B), build tree
`/tmp/ckp908/qc18bacc/build`.  Netlist, pins, die, PDN, IO budget and every flow knob are those of R5a run C
(`qb_col_blk_s20_tt_p1.65_topo`, 390 x 3 110 um, `impl/r5a/col.cfg`); only the placement of the 16 PEs changes.

**Answer.**
- **Hypothesis confirmed for the mechanism, goal not met.**  Tiling a standalone-placed PE into each PE slot
  removes the scatter.  In run B, PE rows have y10-90 81-86 um; R5a run C had 139-621 um.  No PE path is left among
  the post-GRT or routed limiters.
- **Routed fmax (PT, def2spef SPEF, `pt_blk.tcl`): 462.1 / 289.5 MHz tt / ss** [S] vs R5a 410.3 / 243.3 (+12.6 % /
  +19.0 %).  This is short of the 500-MHz goal.
- **New tt limiter:** decode -> broadcast register, `cdr_reg_79_` -> `u_dec` -> BR g1 `nnw_q_reg_8_`, with 0.18 /
  0.14 pF on two repair-buffer nets.  **New ss limiter:** wide lane S2 `sh1 -> y2`.  These are the slice3 non-PE
  limiters (~460-470 MHz class), which PE tiling does not touch.
- **Same die and pins** as R5a (390 x 3 110 um, die / DC 1.566).  **DR: 10 830 markers** after the same 7 iterations
  (C 9 039).
- **Run A** used dense templates (slot utilisation 0.73-0.76, 60-um free stripe).  It **failed**: post-CTS
  legalisation took setup from -0.03 to -0.80 ns (BR -> popcount), post-GRT was -0.896 ns, and DR fell behind C at
  every iteration.  It was stopped after DR iteration 3.  Mechanism in section 3.
- **Gate level:** run B's repaired netlist passes img0 / img1 on 8 abutted copies, 0 errors [M].

## 1. Method (`impl/r5c/`)

Mechanism being fixed (R5a, slice v2, slice3): OpenROAD gpl in this build ignores regions / fences, so the cells of a
PE row are spread over up to 600 um (R5a run C: rows 12 / 13 y10-90 545 / 621 um, bounding box up to 1 053 um tall),
and the PE S2 accumulator drives 0.06-0.12 pF in-PE nets.

1. **PE template** (`pe_tile.cfg` + `place_dump.tcl`, `QC_PNR_TO=place`): the R5a column netlist linked at the PE
   module of row r (`qbc_pe_KB36_ACC_W20_CR1_PP1_<15-r>`; DC uniquified the 16 PEs, so each row gets its own
   template, 8 160-8 380 cells).  Core = the slot, W x 63 rows (113.4 um; the column's PE band is 115.9-117.2 um), pins
   on the neighbour sides (`impl/hard/pe_pins.tcl`: act west, BR outputs east, r + 4 north, r - 4 / lanes south),
   SDC 2.0 ns / 20 % IO, timing-driven gpl, **no DRV repair** (masters = the column's), DPL.  31-160 s per PE.
2. **Tiling** (`place.tcl`, PRE_PLACE_TCL of `col.cfg` = `impl/r5a/col.cfg` + this hook): after the R5a band seed,
   each template is copied into row r's band (`slice_bands.tcl`): x from the core's west edge, y at the first even
   site row at or above the band bottom (row orientation kept: 0 mismatches), by instance name
   `u_core/g_r_<r>__g_c_0__u_pe/<name>`; 132 175 cells matched, 48 PE cells (3 per row) not in the template were left
   to gpl; status **FIRM** (gpl and DPL treat FIRM as fixed).
3. gpl (TD, from the seed, unchanged recipe) places only the other cells (decoders, 8 BRs, feedthrough buffers, lanes,
   banks).  PEs back to PLACED for the DRV repair; the R5a incremental re-spread (`QB_INC_POST`) runs with the PEs
   FIRM again (only repair buffers and non-PE cells move); then PLACED: DPL, CTS, the one setup + one hold repair
   with legalisation, GRT 0.15, DR 7 iterations (`QB_DR_ITER 6`) are exactly R5a run C.
4. Metric (`spread.tcl`, `spread_db.tcl`): per PE row, bounding box and 10-90 % x / y of the cell centres.

Runs: **A** (tau6, from R5a run C's `pdn.odb`): template 320 um wide (PE utilisation in its slot 0.73-0.76, gpl
density 0.80), a 60-um free stripe on the east side.  **B** (tau3, from init, same floorplan / pins): template 376 um
wide = the whole strip (slot utilisation 0.62-0.65, gpl density 0.70); the other cells are placed by gpl into the
templates' white space.  B was started when A's post-CTS legalisation showed the mechanism of 3.

## 2. Results

| quantity | R5a run C (reference) | R5c run A (320-um template) | **R5c run B (376-um template)** | label |
|---|---|---|---|---|
| die / core / die / DC | 390 x 3 110 / 1.178 mm2 / 1.566 | same | **same (1.213 mm2, 1.566)** | [S] |
| PE spread after DPL: max y10-90 / max bbox h x w | 643 um / (route) 1 053 x 380 um | 90 um / 135 x 327 um | **86 um / 128 x 380 um** | [S] |
| rows in order / min in-band | no (1 inversion) / 0.065 | yes / 1.000 | yes / 1.000 | [S] |
| place WNS (all) | -0.557 | -0.424 (dec / BR) | -0.156 (dec / BR) | [S, OR est.] |
| post-CTS: pre-repair / repaired / legalised / + hold | -0.595 / -0.134 / -0.313 / -0.313 | -0.540 / -0.029 / **-0.800** / -0.800 | -0.346 / -0.020 / -0.063 / **-0.076** | [S, OR est.] |
| cell area end / utilisation | 886 268 / 0.752 | 883 346 / 0.750 | 888 388 / 0.754 | [S] |
| post-GRT r2r WNS (fmax) | -0.401 (417 MHz) | -0.896 (346) | **-0.160 (463)** | [S, OR est.] |
| post-GRT worst PE class | pe13 -0.40 | pe13 -0.90 (BR -> popcount S1) | **none violating** | [S, OR est.] |
| DR markers it 0 / 1 / 2 / 3 / 4 / 5 / 6 | 297 935 / 149 192 / 137 999 / 50 533 / 22 953 / 12 420 / **9 039** | 441 520 / 256 461 / 238 412 / 131 531 / stopped | 340 901 / 171 817 / 160 214 / 64 263 / 31 771 / 17 458 / **10 830** | [S] |
| DR marker classes (final) | M2 short 4 711, M3 short 1 224, VIA1 cut 1 026, M2 spacing 955; 82 % in PE rows 0-7, stripes x 175-225 / 325-375 | | M2 short 5 690, M3 short 1 730, VIA1 cut 998, M2 spacing 957, M4 short 477, rest < 400; **9 721 of 10 830 at x 150-225 um**, y 1 400-2 350 (PE rows 1-9) | [S] |
| **PT reg2reg fmax tt / ss** | 410.3 / 243.3 MHz | not routed | **462.1 / 289.5 MHz** | [S] |
| crit path tt | row-13 `stem_p_reg -> acc_reg` (0.06-0.12 pF in-PE) | | `cdr_reg_79_ -> u_dec -> BR g1 nnw_q_reg_8_`, 24 nets, max 0.18 / 0.14 pF (P&R buffer nets of the decode -> BR wire) | [S] |
| crit path ss | same | | wide lane `sh1_reg_1_ -> y2_reg_18_` | [S] |
| hold reg2reg tt / ss | -0.009 / +0.023 | | -0.002 (1 endpoint, `u_pbf p0 -> u_rin`) / +0.010 | [S] |
| IO at P = 2.0 ns tt: south -> reg / act feedthrough | | | -0.101 (`s_rd` -> fused `u_rin`) / 0.069-0.169 ns (budget 0.140 at 2.0 ns: -0.029) | [S] |
| clock insertion L tt / ss | 0.85 / 0.97 ; 1.27 / 1.47 | | 0.85 / 1.01 ; 1.27 / 1.54 | [S] |
| P&R wall (from init) | 2:02 | | 2:22 (+ 16 templates, 4 x ~2.7 min) | [S] |

The PT runs are at a 2.0-ns period.  Reg2reg fmax = 1 / (P - WNS) does not depend on P.  R5a also re-ran its IO
classes at its block fmax (2.44 ns); that was not repeated here (time box).  At 2.16 ns the IO classes scale with P,
so their margins grow [R].

## 3. Mechanisms

**Run A (template 320 um, PE slot utilisation 0.73-0.76) [S, OR est.]: worse than R5a, mechanism = legalisation in
the dense templates.**
- Placement is what the template promised: rows in order, y10-90 81-90 um (R5a 139-621), bounding box <= 327 x 135 um;
  place WNS -0.424 ns, all from decode / BR (-0.42); no PE endpoint violates.
- Post-CTS: setup repair -0.540 -> **-0.029** ns, then its legalisation -> **-0.800** ns (max displacement 124 um; CTS
  legalisation +6 % HPWL, R5a +1 %).  The DRV-repair buffers and the upsized cells have no white space inside a
  0.73-0.76 slot, so DPL pushes them out of it.  Post-GRT r2r **-0.896 ns** (~346 MHz) [OR est.].
- Critical path post-GRT: BR g6 `c_q_reg_313_` (DFQD1) -> DC's CKBD1 broadcast buffer (9 loads, 0.32-ns slew) ->
  CKND4 (16 loads, 0.104 pF) -> row-13 popcount D1 gates at 0.29-0.40-ns slews -> `u_q_reg_98_` (S1).  Violators:
  332 popcount S1 (`u_q`), 127 dec -> BR, 26 S2 accumulator, 20 lanes.  The BRs sit in the 60-um east stripe, so the
  516-bit broadcast of each pair spans the whole 320-um template width of two bands.
- DR: 441 520 / 256 461 / 238 412 / 131 531 markers after iterations 0-3 (C: 297 935 / 149 192 / 137 999 / 50 533),
  iteration 3 took ~60 min; **stopped by me after iteration 3** (no routed result: it could not finish in the box).

**Run B (template 376 um = strip width, slot utilisation 0.62-0.65) [S]: the PE mechanism is gone.**
- Placement: rows in order, y10-90 81-86 um, bounding box <= 380 x 128 um (R5a: y10-90 up to 621 um, box up to
  380 x 1 053 um).  Place WNS -0.156 ns (dec / BR -0.16, lanes -0.05); the DRV-repair buffers now fit in the
  templates' white space (legalisation max displacement 36-60 um, +2 / +1 / 0 / 0 % HPWL).
- Post-CTS: repair -0.346 -> -0.020, legalised **-0.076**, hold legalised -0.076 / +0.018 ns (R5a C: -0.595 -> -0.134
  -> -0.313).  Cell area 888 388 um2 (C 886 268), utilisation 0.754.
- Post-GRT r2r **-0.160 ns = 463 MHz** [OR est.] (C -0.401 = 417 MHz; slice3 461.5).  53 violating endpoints, **none in
  a PE**: dec -> BR `nnw_q` 28 (worst: `cdr_reg_78_` -> decoder -> BR g1 `nnw_q_reg_8_`, -0.160), fused-lane input
  `u_rin` 16, wide lane 9 (-0.16).  These are the slice3 limiters (pnr_slice3.md: wide lane -0.17, dec / BR -0.10,
  routed tt limiter `fs_q` -> fused lanes): with the PEs compact, the column falls back to the ~460-470 MHz class of
  the non-PE logic, which tiling does not touch.
- DR (same 7 iterations as C): see the table; B's markers run ~1.15-1.4x C at every iteration: the PE pin / net
  density (act x code crossbar, R5a 3.3) is now uniform over every band instead of diluted by the scatter.


- B's final markers sit in one vertical stripe, x 150-225 um, in PE rows 1-9.  Net classes: PE rows 3 / 5-9 popcount
  ~1.1-1.7 k each, BR 975, top-level buffers 858.  This is the template's x position of the popcount / BR-broadcast
  crossbar, now stacked at the same x in every row.  Not diagnosed further (time box) [S / R].

**What it would take to reach 500 MHz tt [R]:** the remaining limiters are no longer placement-scatter.
- Decode -> BR: one decoder group drives 8 BRs over 1.6 mm (0.14-0.18 pF repair-buffer nets).  Fix: register at the
  BR side, or a decoder per BR pair.
- Wide / fused lane inputs: the slice3 class.
Both are RTL / floorplan items outside this one-mechanism task.  Mirroring the template in x on alternate rows may
spread the DR stripe.

## 4. Gate-level check

`impl/r5a/gls.sh rcB` (8 abutted instances in `qb_colarr`, act chained through the feedthroughs, VCS zero-delay,
`exp2/core` vectors s0 val 0 / 1) on run B's netlist after the DRV repair, CTS and the post-CTS setup / hold repair
(`write_verilog` of `db/cts_rt.odb`; nothing after that point changes the netlist: antenna repair is off, fillers are
physical-only) [M]:

| netlist | img0 | img1 |
|---|---|---|
| R5c run B, post-repair | **PASS** 630 784 words, 0 errors, 3 644 cycles | **PASS** 630 784 words, 0 errors, 3 684 cycles |

Compile 1:18, peak 838 MB.  Run A's netlist was not simulated (A was stopped before a route).

## 5. Files, commands, disk

New: `impl/r5c/` `pe_tile.cfg`, `place_dump.tcl`, `place.tcl`, `col.cfg`, `spread.tcl`, `spread_db.tcl`.  No existing
script, default or RTL changed.  Summaries: `results/r5c/` (`spread_*.txt`, `summary_*.txt`, `pt_*.txt`, `drc_*.txt`).

```bash
# on tau (from /tmp/ckp908/qc18bacc/repo), B shown (A: QB_TILE_W 320, QB_TILE_DENS 0.80, QC_PNR_FROM=place from r5a_C/db/pdn.*)
for r in $(seq 0 15); do QC_PNR_THREADS=4 QC_PNR_TO=place QB_TILE_W=376 QB_TILE_DENS=0.70 QB_ROW=$r \
  flow/tsmc65/pnr/run_pnr.sh qc18bacc/impl/r5c/pe_tile.cfg r5c_Bt$r; done     # <= 4 in parallel (16 at once thrash)
# tiles: $B/r5c_Btiles/r5c_t<r>/tile.txt
QC_PNR_THREADS=15 QB_CFG=../r5c/col.cfg QB_SYN=qb_col_blk_s20_tt_p1.65_topo QB_BRG=2 QB_PM=seed QB_PNR_PERIOD=2.0 \
  QB_REPIN=2 QB_RT_LOOPS=0 QB_INC_POST=1 QB_GR_ADJ=0.15 QB_W=380 QB_INC_DENS=0.80 QB_DR_ITER=6 \
  QB_TILE_DIR=$B/r5c_Btiles qc18bacc/impl/pnr/run.sh pnr r5c_B
QB_PT_PERIOD=2.0 qc18bacc/impl/r5a/post.sh r5c_B "spef pt"
qc18bacc/impl/r5a/gls.sh rcB <netlist.v> /tmp/ckp908/qc18bacc/r5a_vec/img0 /tmp/ckp908/qc18bacc/r5a_vec/img1
QB5C_DIR=$PWD/qc18bacc/impl/r5c QB5C_DB=<run>/db/route_dr.odb openroad -exit qc18bacc/impl/r5c/spread_db.tcl
```
Results on tau: tau3 `/tmp/ckp908/qc18bacc/build/pnr/r5c_B` (4.5 GB: route, DEF, SPEF tt / ss, PT, `gls/`),
`r5c_Bt0..15` (29 MB each, templates), `r5c_Btiles`, `sim/r5a_rcB`; tau6 `pnr/r5c_A` (564 MB, stopped in DR, no
route DB) and `r5c_t0..15`.  Nothing is left running.  tau3 `/tmp` 70 GB free.  No abstracts / ETMs were made
for B (time box; `impl/r5a/post.sh r5c_B "abs etm"` makes them).
