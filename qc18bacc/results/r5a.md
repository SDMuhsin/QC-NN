# R5a: column hard block `qb_col_blk` for the 8-column abutted array

Labels: **[S]** static (DC / P&R geometry, PrimeTime with the def2spef SPEF, or OpenROAD's own estimate where marked
[OR est.]); **[M]** simulation; **[R]** reasoning from [S] numbers.  Tools as `results/pnr_slice3.md` (DC W-2024.09-SP2
topographical, OpenROAD 2.0-12381, PrimeTime Q-2019.12, VCS S-2021.09).  Hosts **tau3 / tau6** (tau5 / usask `/tmp` are
full: 1.4 / 2.3 GB free); build tree `/tmp/ckp908/qc18bacc/build` on both.

**Answer.**
- **Block:** `qb_col_blk` = one column of the chip's `qb_core` (CREG / WTP / FTP / PPOP, **BRG 2**), plus a buffered
  act feedthrough.
  - DC topographical at 1.65 ns: **774 574 um2** (+7.6 % vs slice3; +20.9 k of that is the 4 608 feedthrough
    buffers), 601.8 / 387.5 MHz pre-route [S].
  - Eight abutted instances of the **routed** netlist are bit-exact on the qb_core bench: img0 / img1, 630 784 words
    each, zero-delay [M].
- **P&R did not reach a DRC-clean route.  The stop rule applied.**
  - Run A was at **5 714 markers at 4 h** (iteration 8: 314 k -> 158 k -> 148 k -> 56 k -> 24 k -> 12.5 k -> 8.2 k
    -> 6.3 k) and was stopped.
  - Sign-off is on run C: the same recipe, 7 iterations, **9 039 markers** [S].  Antenna 0.
- **Strip:** 390 x 3 110 um, die **1.213 mm2**, **die / DC 1.566** (slice3 1.469).  The +15 % core width is set by
  the south pin edge, not by DR [S].
- **Timing (PT, routed SPEF):** reg2reg **410.3 / 243.3 MHz tt / ss** [S].
  - Hold reg2reg -0.009 ns tt (3 endpoints in the parameter bank), +0.023 ss.
  - At the block fmax, every IO budget class passes except the act feedthrough: 0.21 ns tt vs 0.07 P = 0.17 ns.  The
    8-column chain still closes [R].
- **Critical path:** the PE row 13 S2 accumulator, with 0.06-0.12 pF in-PE nets.  Mechanism: rows 12 / 13 placed over
  ~600 um (placement scatter, as slice v2).  It is not logic depth.
- **DR mechanism (measured):** 76 % of the final markers are M1 / M2 / VIA1 pin-access shorts / spacing, and 82 % are
  in PE rows 0-7.  They sit in two x-stripes, one per BRG-2 pair member, on the popcount's act x code input crossbar.  Local cell
  utilisation does not predict them, so a wider strip does not fix them.  Candidate fixes are in 3.3.
- **R5b abstracts:** exact-shape LEF (act / act_o abutment verified, 4 608 / 4 608), ETMs tt / ss / ff, routed
  netlist, DEF and SPEFs.  They describe a route with 9 k DRC markers, so they are usable for R5b floorplanning and
  timing, not for tape-out.


## 1. Block netlist

**RTL** `hw/rtl/qb_col_blk.sv` (new; no existing RTL changed): `qb_core #(ROWS 16, COLS 1, CREG 1, WTP 1, FTP 1,
PPOP 1, BRG 2)`.  This is exactly the configuration of `qb_top.sv` `u_core` (`qb_core #(.CREG(1), .WTP(1), .FTP(1),
.PPOP(1), .BRG(2))`, defaults ROWS 16 / COLS 8 / KB 36 / MWF 28), cut to one column; = `qb_col_cwfp_b2` of slice3 plus
`act_o = act`.  Why a column cut is exact: in `qb_core` every per-column element (decoders, 8 BRs, 16 PEs, 32 fused + 4
wide lanes, parameter records 8c..8c+7, the wide bank's per-column rotation) only uses its column's slice of cd / t2 /
pf / pw / s_rd / w_r; the shared parts (PPU control registers, common mode bits, drain-shift copies, b2 valid) are
duplicated per column with identical inputs.

**Array check (bench)** `hw/tb/qb_colarr.sv` (new): 8 `qb_col_blk` with act chained col c `act_o` -> col c+1 `act`
and qb_core's per-column indexing (fused lane L = 64q + 8c + i, wide L = 8q + c, b2 [64r + 8c +: 8], records 8c + k);
`tb_qb_core.sv -DQBC_COLARR` drives it with the qb_core tile vectors (`exp2/core/img0`):

| check | result |
|---|---|
| RTL, Verilator, img0 | **PASS** 3 644 cycles, 630 784 words, 0 errors [M] |
| DC netlist (s25 run, 8 instances, VCS zero-delay, tcbn65gplus models), img0 | **PASS**, 0 errors [M] |
| same, mutant `QBC_MUT_FT` (one act bit broken before column 5) | caught (MISMATCH b2 / fused) [M] |
| routed netlist: see section 5 | |

**DC** (`impl/run.sh all qb_col_blk 1.65`, topographical, `compile_ultra -no_autoungroup -gate_clock -spg`, hook
`impl/r5a/topo_col.tcl` = slice strip context + IO budget + `set_fix_multiple_port_nets -all -buffer_constants`):

| netlist | IO budget south inputs | cell area | regs | pre-route PT tt / ss (DC parasitics, 1.65 ns) |
|---|---|---|---|---|
| slice3 `qb_col_cwfp_b2` (reference) | 0.20 P | 719 763 um2 | 25 823 | 601.0 / 384.5 MHz |
| `qb_col_blk` s25 (first try, not used) | 0.25 P | 802 229 | 25 823 | |
| **`qb_col_blk` s20 (used)** | 0.20 P | **774 574 um2 (+7.6 %)** | 25 823 | **601.8 / 387.5 MHz** [S] |

Area delta vs slice3 (+54.8 k um2) [S]: the 4 608 act feedthrough buffers outside `u_core` +20.9 k (BUFFD3 / CKND3-4
pairs, sized for the 0.07 P feedthrough budget); the rest is DC sizing noise of the new topology + budget
(broadcast BR -> PE drivers in `u_core` glue, PE +3.8 %, fused lanes +5 %).  The south input budget alone was worth
-27.7 k (0.25 P -> 0.20 P).

## 2. Pin plan and IO budget (for R5b)

Block = strip, die W x 3 110 um (core W - 10 x 3 100, 5-um margin), clk from the north.  Columns abut west-east;
the S macros, write-back and parameter store sit south of the array, the code / weight supply north.

| edge | pins | layers | placement |
|---|---|---|---|
| **west** | `act[4607:0]` (16 rows x 288) | M3 / M5 | row r's 288 bits inside the 15th-85th percentile y range of row r's placed cells (`QB_REPIN 2`) |
| **east** | `act_o[4607:0]` = buffered feedthrough of `act` | M3 / M5 | `act_o[b]` at exactly the y, layer and shape of `act[b]`, so column c's `act_o` abuts column c+1's `act` (checked on the routed block, section 4) |
| **north** | `cd[287:0]`, `ctl[9:0]`, `t2[135:0]`, `clk`, `rst_n` (436) | M2 / M4 / M6 | free order, >= 2 tracks apart |
| **south** | `pf` 653, `pw` 635, `p_ld`, `w_ld`, `s_rd` 544, `w_r` 76, `f_vld/f_src/f_sh/w_vld/w_sh`, `f_y` 544, `f_b` 32, `w_y` 76, `w_b` 4, `f_vld_o`, `w_vld_o`, `b2` 128, `b2_vld` (2 702) | M2 / M4 / M6 | >= 2 tracks apart (spreads them over the whole edge, see 3.2) |
| PG | VDD / VSS = M7 horizontal straps (0.8 um, pitch 30 um, offset 5 um) extended to the west / east boundary | M7 | abut column to column; R5b drops M8 straps (>= 3 um wide, pnr_pe.md) on them |

Signal routing inside the block M2-M7; M8 / M9 are free for the R5b top (PDN, over-the-array routes).
In the array only column 0's `act` and column 7's `act_o` (unconnected) are top-level nets; b2 / lanes / params of
every column leave south, codes north.  An R5b alternative that halves the act chain: drive the act rows from the
middle, columns 0-3 mirrored (MY: act on the east edge).

**IO budget** (`impl/r5a/budget.tcl`, fractions of the period P, relative to the clock at the top-level flops; after
CTS shifted by the block insertion delay L: inputs + L, outputs - L, i.e. a top tree balanced with the block's sinks):

| class | max delay | min delay | meaning |
|---|---|---|---|
| `act` in | 0.55 P | 0.05 P | launch flop + top wire (0.06 P) + 7 upstream feedthroughs x 0.07 P: column 7 is the worst |
| `act_o` out | 0.38 P - U | 0 | feedthrough `act -> act_o` <= 0.07 P per column (U = 0.25 ns setup uncertainty counted once) |
| north in (cd, ctl, t2) | 0.30 P | 0.05 P | code / control broadcast from the north logic |
| south in (pf, pw, *_ld, s_rd, w_r, PPU controls) | 0.20 P | 0.05 P | as the slice runs (0.25 P cost +27.7 k um2 in DC, section 1) |
| south out (f_y, f_b, w_y, w_b, valids, b2) | 0.25 P | 0 | to the write-back / S macros |


## 3. P&R

### 3.1 Recipe (`impl/r5a/col.cfg` = slice3.cfg + block pins / PDN / budget)

As `qcs3_b2i` (pnr_slice3.md): band seed + timing-driven gpl (`QB_PM seed`, BRG 2), DRV repair of violating nets,
`QB_INC_POST` incremental gpl re-spread, DPL, `QB_REPIN 2`, CTS, one setup + one hold repair each legalised
(`QB_RT_LOOPS 0`, IO shifted by `QB_IO_LAT` 0.85 ns; measured insertion 0.82-1.10 ns), GRT (`GR_ADJUST` 0.15), DR.
P&R at 2.0 ns tt.  Block-specific: pins / budget (section 2), PDN `impl/hard/pe_pdn.tcl` (M7 straps = pins).

### 3.2 Runs and what failed (mechanisms) [S]

| run (host) | strip W x H core um | change | outcome |
|---|---|---|---|
| A try 0 (tau3) | 360 x 3 100 | s25 netlist (802 k), pf / pw north, `QB_INC_DENS` 0.80 | **GPL-0302**: after the DRV repair (+13 %, 907 k um2) the strip is at 0.81 > 0.80 target density; stopped |
| A, B try 1 (tau3 380 / tau6 350) | | s20 netlist, all south pins on M2 / M4 / M6, `place_pins -min_distance 1` | **GRT-0119 at the south edge**: 388 / 475 overflowing gcells, all at y < 100 um, x 100-275 um; nets pf / pw / f_y / b2 / s_rd + lane / bank cells.  Mechanism: place_pins packs the 2 702 south pins over the lanes' x range (~46 pins per 3-um gcell vs ~38 tracks) |
| A try 2 (tau3) | **380 x 3 100** | `min_distance 2` tracks (pins forced over the whole edge: 2 880 slots for 2 702 pins) | **GRT clean** at adj 0.15; post-GRT r2r -0.843 ns (PE 12 accumulator: rows 12 / 13 spread over 560-620 um) [OR est.]; DR see 3.3 |
| B try 2 (tau6) | 350 x 3 100 | pf / pw / p_ld / w_ld north (`QB5_PFN 1`: 1 726 north / 1 414 south) | 1 288 parameter nets cross the 3.1-mm strip: repin WNS -1.19 ns, repair_timing > 20 min on 3 489 endpoints; stopped (replaced by C) |
| **C (tau6)** | **380 x 3 100** | = A try 2 from scratch, `QB_DR_ITER 6` (safety route for the 4-h stop rule) | GRT clean; post-GRT r2r **-0.401 ns** (gpl variance vs A) [OR est.]; DR see 3.3 |

Strip area cost [S / R]: core 380 x 3 100 = 1.178 mm2 vs slice3 330 x 3 100 = 1.023 mm2 (+15.2 %).
- +7.6 % of it carries the larger netlist at the same utilisation (355 um).
- The other +7 % lowers the post-repair utilisation to 0.752 (slice3 0.805) and is what the south pin edge needs:
  2 702 pins at 2-track spacing on M2 / M4 / M6 need >= 362 um.  350 um gives 2 625 slots.
- The lower utilisation did not buy DR convergence (3.3).  The pin edge did need the width.

### 3.3 Detailed route

Markers after each DR iteration [S] (OpenROAD DRT-0199; slice3 `qcs3_b2i` for reference):

| iteration | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| slice3 `qcs3_b2i` (330 um, no feedthrough, all south pins on M4 / M6) | 240 k | 142 k | 134 k | 18 k | **9 130** (end) | | | | |
| **A** (380 um, 40 iterations allowed) | 313 610 | 157 669 | 148 251 | 55 858 | 24 234 | 12 536 | 8 214 | 6 306 | 5 714 at 70 % -> **stopped at 4 h (stop rule)** |
| **C** (380 um, `DR_END_ITER` 6 = 7 iterations) | 297 935 | 149 192 | 137 999 | 50 533 | 22 953 | 12 420 | **9 039** (end) | | |

Iteration wall time A: 11 / 11 / 11 / 30 / 19 / 13 / 10 / ~7 / ~6 min (15 threads, tau3).  The decay from iteration 4 on
is ~0.65 per iteration (24.2 k -> 12.5 k -> 8.2 k -> 6.3 k -> ~5.5 k), i.e. slowing: < 1 000 would take > 5 more
iterations (~35 min) if the ratio held, and it is flattening [R].

**Where the markers are (C, final 9 039)** [S] (`impl/r5a/drc_hist.py`, `corr.py`, `density.tcl` on `route_dr.odb`):
- **Type / layer:** M2 shorts 4 711, M3 shorts 1 224, VIA1 cut spacing 1 026, M2 spacing 955, M4-M7 < 700 together.
  This is local pin-access / first-layer congestion, not global capacity (GRT is clean).  A's tables per iteration
  show the same mix.
- **Where:** PE rows 0-7 (y 1 300-2 100 um: 7 373 of 9 039 markers, the 50-um bins at y 1 350 / 1 500 / 1 750 alone 4 179).
  Two vertical stripes, x 175-225 um (4 147) and x 325-375 um (3 295).  The two rows of a BRG-2 pair co-place side by
  side, so each stripe is one PE's popcount cluster.  The south pin edge is clean (2 markers): the try-1 GRT failure
  is fixed.
- **Nets in the stripes:** PE popcount internal nets (`g_pop2_u_pop/n*`, 6 957 hits), `u_core/n*` (3 317: the
  BR -> PE broadcast inverters / CKND12 drivers of the decoded codes), `a_q` (1 895: act register -> popcount).
  This is the act x code input crossbar of the popcount: 288 act bits x 360 code bits per PE, wired into
  high-fan-in AOI / XOR cells.
- **Not utilisation:** per-50-um-bin cell utilisation (fillers excluded) does not predict the markers.  Quintiles:
  util 0.00-0.65 -> 1.8 markers per bin, 0.66-0.79 -> 26.0, 0.79-0.82 -> 14.4, 0.82-0.83 -> 30.3, 0.83-0.96 -> 21.3.
  It is the net / pin density of the popcount logic class, which lowering the strip utilisation does not remove:
  A / C at 0.755 converge no better than slice3 at 0.805.
- **Global route agrees:** the hottest M2 guide-demand bins of A (`guide_map.py` on `route.guide`) are PE bins at
  x 200-350 um (~1.6x the strip mean), and the south edge.

**Fixes not run (time box), with expected cost** [R]:
1. DPL cell padding (`set_placement_padding -instances`, 1 site each side) on the PE popcount cells only.  It spreads
   their pins without moving the PE rows.  Cost: about +8-10 % strip area if the popcount is ~55 % of PE area.
2. Let the block route M8 as well (signals M2-M8; top PDN on M9 only).  This adds vertical escape over the popcount
   clusters, at no area cost, but the R5b PG pins move to M8.
3. A per-region `GR_ADJUST` on M2 / M3 over the PE band, so GR spreads the crossbar wiring before DR.
4. More DR iterations: the runs show a slowing tail (~0.65x per iteration), but no stall yet.





## 4. Sign-off

Routed block = **run C** (7 DR iterations, 9 039 markers): the best complete route at the 4-h stop rule.  A's DR
was further along (5 714 at 4 h) but was killed mid-iteration, so it has no database.  def2spef tt / ss / ff,
PrimeTime with propagated clocks, IO budget of section 2 shifted by the measured insertion delay L
(`impl/r5a/pt_blk.tcl`).  7 505 of 265 985 nets are not annotated (driverless `SYNOPSYS_UNCONNECTED`, as slice3).

| quantity | tt | ss | label |
|---|---|---|---|
| **die** | 390 x 3 110 um = **1.213 mm2**; core 1.178 mm2 | | [S] |
| die / DC cell area (774 574 um2) | **1.566** (core 1.521); slice3: 1.469 (core 1.421) | | [S] |
| cell area after P&R / utilisation | 886 268 um2 (x1.144 of DC) / 0.752 | | [S] |
| **reg2reg fmax** | **410.3 MHz** (WNS -0.437 at 2.0 ns) | **243.3 MHz** (-2.110 at 2.0 ns) | [S] |
| slice3 routed, same flow (reference) | 472.8 | 290.3 | [S] |
| post-GRT estimate (C) | 417 MHz (-0.401) | | [S, OR est.] |
| clock insertion L (min / max sink) | 0.85 / 0.97 ns | 1.27 / 1.47 ns | [S] |
| **hold reg2reg** | **-0.009 ns, 3 endpoints** (`u_pbf` p0 -> late, same-bank shift) | +0.023 ns, 0 | [S] |
| hold IO (min budget 0.05 P + L) | +0.051 (ctl -> ctlr) | +0.117 | [S] |
| IO at the block's fmax (P = 2.44 tt / 4.11 ss): act -> reg | +0.672 | +1.300 | [S] |
| north -> reg (t2 -> BR) | +0.724 | +1.496 | [S] |
| south -> reg (s_rd -> fused lane input) | +0.253 | +0.528 | [S] |
| reg -> south (b2) | +0.916 | +1.871 | [S] |
| **act -> act_o feedthrough** (budget 0.07 P) | **0.110-0.209 ns** (budget 0.171): -0.038 | **0.175-0.331 ns** (budget 0.288): -0.044 | [S] |
| DRC (OpenROAD DR) | **9 039 markers** | | [S] |
| antenna (`check_antennas`, routed) | 0 net / 0 pin violations | | [S] |

**Critical path (tt and ss, same path)** [S]: PE row 13, S2.
- `g_pop2_stem_p_reg` (DFQD4) -> CKBD4 -> stem / g3n MUX2D0 -> 4:2 compressor (CMPE42D2) -> 20-b accumulator
  carry chain (FA1D4 x 4, IOA21 / ND2) -> XOR2D4 driving **0.12 pF** (`n509`, 4 loads) -> XOR2D2 (0.06 pF,
  9 loads) -> ND2D1 / OAI211D2 / NR2D1 / INVD1 / AOI21 / OAI21 -> `acc_reg_119_`.  Arrival 3.09 ns tt.
- Mechanism (placement, as slice v2): rows 12 / 13 are placed over y 2 160-2 760 um (`repin` ranges; slice3 max span
  509 um).  The accumulator's internal nets are 0.06-0.12 pF where DC assumed a compact PE.  DC closes the same logic
  at 601.8 MHz tt.  Gpl variance between runs of the same recipe is large: A has a post-GRT WNS of -0.843 ns (PE 12),
  C -0.401 ns.
- The act feedthrough misses its 0.07 P budget by 0.04 ns (0.21 ns tt per column).  The R5b chain still closes [R]:
  column 7 arrives at 0.06 P + 7 x 0.209 ns + ~0.10 ns (act -> a_q) = 1.71 ns < P - U = 2.19 ns at 410 MHz.  Else drive
  act from the middle (4 hops).

**Abstracts for R5b** (`/tmp/ckp908/qc18bacc/build/pnr/r5a_C/out/` on tau6):
- `qb_col_blk.lef`: `write_abstract_lef -bloat_factor 0`, exact shapes; 12 356 pins (4 608 act + 4 608 act_o +
  3 138 north / south + VDD / VSS on M7).  Abutment check on the routed db: **4 608 / 4 608** act / act_o pairs on the
  same layer and y at the west / east die edges, 0 bad.
- ETMs `etm/qb_col_blk_{tt,ss,ff}.lib` + `_lib.db`: PrimeTime `extract_model -library_cell` on the routed netlist +
  SPEF.  tt: 12 356 pins, combinational act -> act_o arcs, 6 959 setup arcs, area 885 870.
- Routed netlist `qb_col_blk.v` / `_pg.v`, DEF, SPEF tt / ss / ff (`_pt` = PrimeTime naming).


## 5. Gate-level check

`impl/r5a/gls.sh`: VCS S-2021.09 zero-delay (`+nospecify +notimingcheck`, tcbn65gplus cell models), 8 instances of
the netlist in `qb_colarr` (act chained through the feedthroughs), `tb_qb_core.sv -DQBC_COLARR`, vectors
`exp2/core/img0` / `img1` (s0 val 0 / 1, all 21 passes):

| netlist | img0 | img1 |
|---|---|---|
| DC (pre-P&R) | PASS 630 784 words, 0 errors, 3 644 cycles | |
| **routed (run C: CTS buffers, repairs, act feedthroughs)** | **PASS** 630 784 words, 0 errors, 3 644 cycles | **PASS** 630 784, 0 errors, 3 684 cycles |
| mutant `QBC_MUT_FT` (DC netlist) | caught | |

No SDF run (the route has 9 k DRC markers; SDF from it would not be sign-off parasitics either).


## 6. Files, commands, disk

New:
- RTL / bench: `hw/rtl/qb_col_blk.sv`, `hw/rtl/qb_blk.f`, `hw/tb/qb_colarr.sv`.
- `impl/r5a/`: `topo_col.tcl`, `budget.tcl`, `col.cfg`, `pins.tcl`, `repin.tcl`, `post.sh`, `pt_blk.tcl`, `etm.tcl`,
  `gls.sh`, `drc_hist.py`, `guide_map.py`, `density.tcl`, `corr.py`.

Changed (defaults unchanged):
- `hw/tb/tb_qb_core.sv`: `QBC_COLARR`.
- `impl/pnr/slice_post_cts.tcl`: per-class IO budget when `QB_IO_BUDGET` is set.

Run summaries: `results/r5a/run_C.txt`, `run_A.txt`.  Builds stay on tau.

```bash
# on tau6 / tau3 from /tmp/ckp908/qc18bacc/repo
QC_TOPO=1 QC_HOOK=$PWD/qc18bacc/impl/r5a/topo_col.tcl QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" \
  QB_FL=$PWD/qc18bacc/hw/rtl/qb_blk.f qc18bacc/impl/run.sh all qb_col_blk 1.65 qb_col_blk_s20_tt_p1.65_topo
QB_CFG=../r5a/col.cfg QB_SYN=qb_col_blk_s20_tt_p1.65_topo QB_BRG=2 QB_PM=seed QB_PNR_PERIOD=2.0 QB_REPIN=2 \
  QB_RT_LOOPS=0 QB_INC_POST=1 QB_GR_ADJ=0.15 QB_W=380 QB_INC_DENS=0.80 QB_DR_ITER=6 qc18bacc/impl/pnr/run.sh pnr r5a_C
qc18bacc/impl/r5a/post.sh r5a_C                      # SPEF ss/ff, PT tt/ss (QB_PT_PERIOD), LEF + abutment + antenna, ETMs
qc18bacc/impl/r5a/gls.sh rtC $B/pnr/r5a_C/out/qb_col_blk.v <img0> <img1>
```

**Results on tau** (`/tmp/ckp908/qc18bacc/build`):
- tau6: `pnr/r5a_C` (5.5 GB: route, LEF, ETMs, SPEFs), `syn/qb_col_blk_s20_tt_p1.65_topo`, `sim/r5a_rtC`.
- tau3: same netlist copy; `pnr/r5a_A` (logs only).

**Deleted (own, superseded):**
- tau6: `pnr/r5a_B` (708 MB), `syn/qb_col_blk_pfn_tt_p1.65_topo` (270 MB), simv / csrc of `sim/r5a_dcpfn*`.
- tau3: `syn/qb_col_blk_tt_p1.65_topo` (295 MB, s25 netlist), `pnr/r5a_A/db` + `route.guide` (~770 MB).
- tau3 / tau6 `/tmp` free after: 75 GB each.

Nothing is left running.

