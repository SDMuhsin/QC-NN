# Column slice of qb_core, second P&R probe: code-register removal, retimed tails, DC margin, complete route

Labels: **[M]** measured (bench / simulation), **[S]** static: synthesis / P&R geometry, PrimeTime (PT) with the
def2spef SPEF, or OpenROAD's own estimate where marked "OR est."; **[R]** reasoning / estimate derived from [S] numbers.
Tools as `results/pnr_slice.md` (DC 2024.09 topographical, OpenROAD 2.0-12381, PrimeTime Q-2019.12); hosts tau5 and
usask (tau-02), kit-derived views in `/tmp/ckp908/qc18bacc/build`.  Previous probes: `results/pnr_slice.md` (slice v1,
`qcs_t1`), `results/pnr_core.md` (8 x 2 proxy).

**Stop-rule status.  Detailed route did not complete inside the time box; the last completed stage is
post-global-route (OpenROAD global-route parasitic estimates, reg2reg, tt).  No routed SPEF, so no PrimeTime sign-off
and no routed DRC count.**  Detailed route did not crash this time (no SIGSEGV in either attempt, `-or_seed` 3 / 11,
12-15 / 16 threads), but it converged far more slowly than slice v1: 335 k -> 233 k -> 218 k -> 127 k markers after 4 of 8
iterations (`qcs2_a`, ~110 min; iteration 5 at 20 % when I stopped it at the time box) and 317 k -> 214 k -> 202 k
(`qcs2_b`, stopped by me after 3 iterations, ~20 min / iteration, 20 configured).  v1 had 252 k -> 122 k -> 115 k
-> 35 k at the same point.  Global route itself failed three times (GRT-0119, left-edge horizontal overflow) before the
pin re-placement + `GR_ADJUST` 0.15 recipe passed (section 3).

**Answer.**  The RTL items work: CREG removes 5 783 flops / 33.6 k um2 per column (-4.8 %; -0.27 mm2 for the 16 x 8
core) at unchanged port timing, and the retimed tails + the PE weighted-sum retiming let DC close the column at 1.65 ns
for +0.9 % area over R1 (pre-route PT 600.7 / 385.2 MHz tt / ss vs 495.7 / 311.9).  The physical result is worse than
v1, for a reason the RTL did not cause: **post-GRT 279 MHz tt [S, OR est.] (WNS -1.586 ns at 2.0 ns; second run 252
MHz)**, limited by **PE rows 11, 14, 15 (and 9, 12)**, whose S2 accumulators sit in the over-full upper strip where
global placement mixed rows 8-15 (placed centroids out of order by up to two bands); there the D1 gates DC sized for
1.40 ns drive 0.06-0.10 pF of detoured wire (1.0-ns slews).  Every other class is within -0.18 ns post-GRT:
**fused / wide lanes, decoders / BR and PE rows 0-8 would give ~460 MHz post-GRT [S, OR est.]**.  Core / DC 1.456 at
global route (v1 1.469).

## 1. RTL changes (all as parameters of `qb_core`, default 0 = R1 as built; `qb_core.sv` / `qb_lane_f.sv` defaults unchanged)

| parameter | change | latency / contract | bench |
|---|---|---|---|
| `CREG` | codes `cd` and item controls `ctl` registered at the port (cycle n), decoded (`qbc_coldec`), then BR at edge n + 1; BR's codes / NNw / ctl drive the PE popcount directly (`qbc_pe #(CR 1)`: only the act bytes keep an S0 register).  `b2_vld` delay chain 3 -> 2 (BR is one cycle later) | **unchanged** at every port: code -> popcount, act -> popcount, T2 -> comparator, b2 / b2_vld | R1 bench PASS |
| `WTP` | wide lane (`qbcw_lane #(TP 1)`): S3 = `y2 + r2` (20 b, registered with the u8 clamp of y2, mode, T); S4 = saturation, output mode and the compare `ys > T`, evaluated in parallel on the registered sum (`hi ? 32767 > T : lo ? -32767 > T : s > T`) | wide-lane latency 4 -> **5**: `w_vld_o / w_y / w_b` one cycle later (lane cycle e + 5) | R1 bench PASS |
| `FTP` | fused lane (`qbf_lane #(FP 1)`, new `qbf_fin_a` / `qbf_fin_b`; `qbf_fin` kept): A = window shift + `y + h + rs + round` (19 b registered with mode, T), B = saturation / output mode / compare in parallel as above | fused-lane latency 3 -> **4**: `f_vld_o / f_y / f_b` one cycle later (lane cycle e + 4) | R1 bench PASS |
| `PPOP` | PE: S1 registers the four 5-b group popcounts per lane (`qbc_pe_pop_u`, 160 b instead of the 80-b weighted sum); the weighted group sum (stem weights, g3n) and - NNw move into S2 in front of the accumulator add (`qbc_pe_acc_u`), NNw / stem / g3n pipelined one stage | **unchanged** (internal retiming) | R1 bench PASS |

Synthesis tops (`hw/rtl/qb_col.sv`, same ports as `qb_col`): `qb_col_c` (CREG), `qb_col_cw` (+ WTP), `qb_col_cwf`
(+ FTP), `qb_col_cwfp` (+ PPOP).  Bench: `tb_qb_core.sv` takes `-DQBC_CREG=1 -DQBC_WTP=1 -DQBC_FTP=1 -DQBC_PPOP=1`
(via `QBC_DEFS`); it compares every output word in order on its valid, so the lane-latency change needs no vector change.

**Contract change for R3** (WTP + FTP): the PPU outputs leave one cycle later: fused results at lane cycle e + 4 (was
e + 3), wide results at e + 5 (was e + 4); inputs (f_* / w_* controls at t, late operands s_rd / w_r at e + 1) are
unchanged.  The R3 sequencer / S writer must time the write-back of `f_y` / `w_y` (and `f_b` / `w_b` to the binary
maps) one cycle later; in the compiler's schedule every pass's write-completion time moves by + 1 cycle, so a RAW-bound
tile start (a consumer pass waiting for the last write of its producer) can move by + 1 cycle [R] (upper bound
~ one cycle per RAW-bound pass switch, i.e. tens of cycles on ~3 650 cycles / image; to be re-run in compile/ for R3).

### 1.1 Bench results [M]

Vectors exported fresh (`export_core.py` on E6_s0 `/tmp/root/qc18b/exc200/E6_s0/best.pt`, val 0 / 1;
`export_act2.py` val 0), Verilator 5.050:

| build (`QBC_DEFS`) | val 0 | val 1 |
|---|---|---|
| default (R1, no defines) | PASS, 3 644 cycles, 630 784 words, 0 errors | PASS, 3 684 cycles, 630 784 words, 0 errors |
| `CREG` | PASS, 0 errors | PASS, 0 errors |
| `CREG WTP FTP PPOP` (the P&R netlist) | PASS, 0 errors (21 passes) | PASS, 0 errors |
| same + mutant `QBC_MUT_INV` / `_NNW` / `_ROT` | FAIL 9 216 / 65 536 / 13 763 errors (caught) | |
| R2b `run_tb_act2.sh` (qb_act2, unchanged RTL) | PASS: 2 880 items, 600 tiles, 0 tile-cycle mismatches, 0 errors | |

## 2. Synthesis (DC topographical, strip context `topo_strip.tcl`, tt) [S]

**Setup margin**: DC clock period **1.65 ns** (setup uncertainty 0.25 ns as always, so reg2reg is closed at 1.40 ns
of logic + setup), IO delays 20 % of 1.65 ns; P&R and PT re-time the same netlist at **2.0 ns** (`QB_PNR_PERIOD`,
`QB_PT_PERIOD`).  Pre-route PT with the DC topographical parasitics:

| top | DC period | cell area um2 | regs | PT tt / ss fmax MHz |
|---|---|---|---|---|
| `qb_col` (R1, pnr_slice.md) | 2.0 | 696 140 | 25 652 | 495.7 / 311.9 |
| `qb_col_c` (CREG) | 2.0 | **662 567** | **19 869** | 496.0 / 313.7 |
| `qb_col_cwfp` | 2.0 | 672 368 | 22 727 | 494.6 / 313.7 |
| `qb_col_cw` | 1.65 | 738 055 | 20 070 | 599.7 / 385.3 |
| `qb_col_cwf` | 1.65 | 728 238 | 21 255 | 601.2 / 384.5 |
| **`qb_col_cwfp`** (P&R netlist) | 1.65 | **702 344** | 22 727 | 600.7 / **385.2** |

**Item 1, CREG** (same 2.0-ns topographical recipe): **-5 783 flops** per column (-16 x 380 PE S0 code / NNw / ctl
bits + 298 port bits, exactly the RTL count) and **-33 573 um2 (-4.8 %)** per column [S]; x 8 columns = **-0.269 mm2
pre-route** for the 16 x 8 core [R] (R1 estimate -0.32 mm2).  Pre-route fmax unchanged (DC's worst path moves to
BR -> popcount: the BR register is now the S0 stage of 8 PEs).

**10 % rule (item 2)**: DC closes every path to the target, so the classes were compared at the over-constrained
target (worst setup path per endpoint class, PT tt on the DC parasitics, `impl/pt_class.tcl`).  With only CREG + WTP
(`qb_col_cw`, 1.65 ns), the fused-lane tail (`u_rlate -> u_rout`, slack -0.011 ns), the PE S1 popcount (BR -> s_q,
-0.004) and the PE S2 accumulator (-0.017) all sit at the critical slack (the target is met only by sizing): within
10 % -> the fused tail was split (FTP) and the PE weighted sum retimed into S2 (PPOP).  The wide tail after the split
has +0.06 ns.  Effect on area at the same 1.65-ns target: cw 738 055 -> cwf 728 238 (-1.3 %) -> cwfp 702 344
(-3.6 %): the extra registers (+2 657) cost less than the upsizing they avoid.  Cost of the margin at fixed RTL:
cwfp 1.65 vs 2.0 ns **+29 976 um2 (+4.5 %)**; cost of the retiming registers at 2.0 ns: cwfp vs c +9 801 (+1.5 %).
Net vs R1 `qb_col` at 2.0 ns: 702 344 vs 696 140 (+0.9 %) with a +24 % faster pre-route ss (385 vs 312 MHz).

## 3. P&R flow (`impl/pnr/slice.cfg`, same recipe as `qcs_t1` except as listed)

| item | value |
|---|---|
| netlist | `qb_col_cwfp_tt_p1.65_topo` (702 344 um2); P&R / estimates at **2.0 ns** (`QB_PNR_PERIOD 2.0`: clock, IO delay 0.4 ns, max transition 0.2 ns rescaled in the P&R SDC) |
| floorplan / pins / seed / gpl / DRV / CTS | as `qcs_t1`: strip core 330 x 3 100 um (die 340 x 3 110), utilisation 0.687 of DC; band seed, timing-driven gpl; `repair_design` on 11 741-11 785 violating nets; CTS `-balance_levels`; CREG port registers seeded with the decoders (`slice_bands.tcl`) |
| post-CTS repair (`slice_post_cts.tcl`, `QB_RTSEQ 2`) | each repair followed by legalisation + re-estimate + counts: setup repair -> legalise -> hold repair (margin 0.02, <= 10 %) -> legalise -> (`QB_RT_LOOPS` rounds of setup repair -> legalise -> hold repair if needed) |
| pins (`QB_REPIN 2`, new `slice_repin.tcl`, PRE_CTS) | after placement the act / b2 pins of PE row r move to the 15th-85th percentile y range of row r's placed cells (regions may overlap) |
| global route | `GR_ADJUST` **0.15** (`QB_GR_ADJ`; v1 0.25) |
| detailed route | `QB_DR_ARGS -or_seed 3` / `11`, 15 / 16 threads, 8 / 20 iterations |

**Legalisation vs setup (measured, tt, OpenROAD placement estimates) [S, OR est.]**:

| step | `qcs2_a` WNS ns (viol. endpoints) | `qcs2_b` |
|---|---|---|
| CTS, before repair | -0.831 (314) | -0.833 (337) |
| setup repair (cells resized in place, not yet legal) | -0.350 (14) | -0.270 (9) |
| + legalisation | -0.541 (228) | -0.419 (182) |
| hold repair (+1 477 buffers) + legalisation | **-0.576** (292), hold +0.002 | -0.564 (246), hold +0.014 |
| first try only: setup repair again + legalise (round 1) | -0.548 -> -0.718 | -0.419 -> -0.839 |
| first try only: round 2 | -0.718 -> -1.043 | -0.803 -> -1.211 |

So **re-running `repair_timing -setup` after the hold repair does not work in this build**: each round "repairs" to
~-0.4 / -0.5 ns on overlapping cells and legalisation then loses more than was gained (HPWL +2 % per round, max
displacement 100-110 um), and the extra upsizing filled the strip (cells 826 k um2) so that global route failed.  What
worked is a single setup + hold round, each followed by legalisation (`QB_RT_LOOPS 0`): legalisation after the hold
repair costs only 0.035 / 0.145 ns there.  Incremental legalisation (`detailed_placement` already moves only
overlapping cells: average displacement 0.6-0.7 um) is not the issue; the loss comes from the few cells displaced by
~100 um around the upsized critical cells.

**Global route** [S]:

| run | pins | GR_ADJUST | post-CTS repair | result |
|---|---|---|---|---|
| `qcs2_a`, `qcs2_b` try 1 | bands (v1) | 0.25 | 2 extra rounds | **GRT-0119**: horizontal overflow at x 0-3 um, y 2.39-2.70 mm (14-15 k gcells), sources `act[2304..3167]` = rows 8-10 (cells placed up to 2 bands above their pins) |
| `qcs2_a` try 2 | `QB_REPIN 1` (pins between centroid midpoints) | 0.25 | single round | GRT-0119 again: rows 9-12 / 14 centroids are out of order (row 10 at y 2 261 below row 9 at 2 459; row 14 at 2 685 below row 13 at 2 741), so their pins were squeezed into 40-110-um ranges |
| `qcs2_a` try 3, `qcs2_b` try 2 | `QB_REPIN 2` (percentile ranges, overlapping) | **0.15** | single round | **clean**; post-GRT r2r WNS -1.586 / -1.965 ns |

## 4. Results

| quantity | slice v2 `qcs2_a` (this) | slice v1 `qcs_t1` (pnr_slice.md) | 8 x 2 proxy (pnr_core.md) | label |
|---|---|---|---|---|
| RTL | CREG + WTP + FTP + PPOP | R1 | R1 (2 columns) | |
| DC cell area | **702 344 um2** (topo, 1.65 ns; 22 727 regs) | 696 140 (topo, 2.0 ns; 25 652 regs) | 921 629 (WLM) | [S] |
| pre-route fmax tt / ss (PT, DC parasitics) | **600.7 / 385.2 MHz** | 495.7 / 311.9 | 500.4 / 316.6 | [S] |
| die / core | 340 x 3 110 = 1.057 mm2 / 1.023 mm2 | same | 1.586 / 1.535 mm2 | [S] |
| cell area place / CTS / after repair (x DC) | 795 827 (x1.133) / 821 656 (x1.170) / **824 768 (x1.174)** | x1.118 / x1.155 / x1.169 | x1.128 / x1.168 | [S] |
| utilisation floorplan / place / end | 0.687 / 0.778 / 0.806 | 0.681 / 0.761 / 0.796 | 0.60 -> 0.70 | [S] |
| **core / DC area** | **1.456** at global route (die / DC 1.506) | 1.469 at global route | 1.665 routed | [S] |
| global route | clean only with repin + GR_ADJUST 0.15 (3 GRT-0119 failures before) | clean (0.25) | clean | [S] |
| detailed route / DRC | **not completed**: 127 k markers after 4 of 8 iterations (b: 202 k after 3 of 20); no crash | 940 after 10 iterations, then SIGSEGV | 58 markers (routed) | [S] |
| **fmax reg2reg tt** | **279 MHz post-GRT** [OR est.] (WNS -1.586; `qcs2_b` 252) | 366 post-GRT [OR est.] | 322.5 routed (PT); 311 post-GRT | [S] |
| same, PE rows 9 / 11 / 12 / 14 / 15 excluded | ~460 MHz (lanes -0.18, BR/dec -0.15, rows 0-8 >= -0.12 ns) [OR est.] | | | [S] |
| fmax ss | ~180 MHz [R] (pre-route ss / tt 0.64) | ~230 [R] | 201.5 routed (PT) | [R] |
| critical path | PE row 11 S2: `g_pop2_stem_p_reg` -> weighted group sum (4:2 compressors) -> 20-b accumulator add -> `acc_reg_19` (23 stages, 3.49 ns) | wide lane S3 `r2 -> b_o` (2.47 ns) | fused lane `u_rlate -> u_rout` | [S] |
| wire share of the critical path | net RC 2.4 %, 0 P&R buffers; but 4 D1 gates driving 0.06-0.095 pF (~400-500 um of wire, slews 1.0 ns) take 1.85 of the 3.49 ns | net 0.2 % + 1 buffer | net 1.7 % + 38 % repeaters | [S, OR est.] |
| hold (tt, reg2reg) | +0.002 post-CTS repair; **-0.283 post-GRT** [OR est.] | +0.019 / -0.027 | PT -0.012 | [S] |
| clock latency post-GRT | 0.90-1.73 ns (v1 0.76-1.16) | | | [S, OR est.] |
| PrimeTime with SPEF (tt / ss) | **not run** (no routed DEF) | not run | run | |

Post-GRT worst slack per class (`qcs2_a`, `est_grt_tt.ends.rpt`) [S, OR est.]: PE row 11 -1.59 (119 violating
endpoints), row 14 -1.37 (133), row 15 -1.31 (92), row 12 -0.42, row 9 -0.39; fused lanes -0.18 (u_pbf -> u_rin),
wide lanes -0.16 (S2 `sh1 -> y2`), decode / BR -0.15 (`cdr -> nnw_q`, 1 P&R buffer), PE rows 0-8 and 13 >= -0.12.
The retimed tails are no longer near-critical anywhere (wide S3 / S4, fused S2a / S2b do not appear among the
violators).

## 5. Critical-path mechanism

1. **Logic depth is no longer the limiter.** At DC (1.65 ns) and at placement the classes are balanced (post-CTS
   -0.58 ns worst, PE row 14 comparator over 12 P&R buffers, 20 % repeater share).
2. **Placement of the upper PE rows.** The seeded bands hold in order for rows 0-8 (placed centroids monotone, 0-100 um
   below the band centre) but rows 9-15 are mixed by global placement: row 9 at y 2 459, row 10 at 2 261, row 12 at 2 489, row 14 at
   2 685 below row 13 (2 741), row 15 at 2 816 for a band at 3 046 (`slice_repin.tcl` log).  The rows' act pins then
   sit up to two bands away from their PE (the GRT-0119 overflow of try 1 / 2, and of v1's `qcs_t6`) and the cells of
   one PE are spread over the mixed region.  This is the same drift as v1 (rows 11-15) and gets worse here: the CREG
   BR of group 1 now feeds the popcount logic of rows 8-15 directly (360 code bits x 8 PEs of logic pins instead of 8
   register pins), which plausibly pulls the group's PEs towards its centre [R, not isolated: no v2 run without CREG];
   the strip is at 0.80 utilisation.
3. **Global route in the congested region** (GR_ADJUST 0.15) detours the intra-PE nets of those rows: the S2 accumulator
   of row 11 has D1-sized NR2 / AOI21 / INV stages each driving 0.06-0.10 pF with 1.0-ns slews (0.25-0.63 ns per
   stage); the placement estimate saw -0.58 ns, global route -1.59 ns.  Wire *RC* stays 2-5 % of the path; the cost is
   the wire *capacitance* on gates DC sized for a short net.
4. Clock: post-GRT latency 0.90-1.73 ns on the 3.1-mm strip (v1 0.76-1.16), i.e. skew grew with the congested
   upper half too.

## 6. What would fix it [R]

1. **Fixed (not seeded) placement of PE rows 8-15 and of BR group 1**: the measured failure is placement order, not
   logic; pre-place each PE row as a block (or a newer OpenROAD whose gpl honours fences).  With rows 0-8 behaviour
   everywhere the post-GRT limit is the lanes / decode at ~-0.18 ns (~460 MHz est.).
2. **Duplicate BR per 4 rows** (`ROWS / 4` groups; +2 x 380 flops per column, still -5 023 of the 5 783 saved; needs a BR-group parameter, not built): halves
   the span and the logic fan-out each BR drives.
3. **Repair at global-route parasitics** (POST_GRT_TCL `repair_timing` + incremental global route) instead of a
   second post-CTS round.  Tried on `qcs2_b` (`QB_GRT_REPAIR 1`: repair_timing at GRT parasitics from -1.965 ns, 592
   violating endpoints: 152 buffers, 2 607 resized; legalisation HPWL +4 %, max displacement 131 um), but the
   incremental global route (`global_route -end_incremental`) did not finish in 75 min (single thread) and was stopped:
   no number [S: negative result on runtime only].
4. Detailed-route runtime: a full DR of this strip at 300 k initial markers needs > 3 h; route with GR_ADJUST 0.25
   once the pin / row order is fixed (v1 converged ~2x faster per iteration).

## 7. Files and commands

RTL: `hw/rtl/qb_core.sv` (parameters CREG / WTP / FTP / PPOP; new `qbc_pe_pop_u`, `qbc_pe_acc_u`; `qbcw_lane #(TP)`),
`hw/rtl/qb_lane_f.sv` (`qbf_lane #(FP)`, new `qbf_fin_a`, `qbf_fin_b`), `hw/rtl/qb_col.sv` (tops `qb_col_c`, `_cw`,
`_cwf`, `_cwfp`).  Bench: `hw/tb/tb_qb_core.sv` (QBC_CREG / WTP / FTP / PPOP defines).  Impl: `impl/pt_class.tcl`
(per-class worst path), `impl/pnr/slice.cfg` (QB_PNR_PERIOD, QB_REPIN, QB_GR_ADJ, QB_DR_ARGS), `slice_post_cts.tcl`
(QB_RTSEQ / QB_RT_LOOPS), new `slice_repin.tcl`, `slice_pins.tcl` (QB_PIN_Y), `slice_bands.tcl` (CREG registers),
`grt_est.tcl` (QB_GRT_REPAIR), `run.sh` (QB_PT_PERIOD).

```bash
QBC_TAG=_v2 QBC_DEFS="-DQBC_CREG=1 -DQBC_WTP=1 -DQBC_FTP=1 -DQBC_PPOP=1" qc18bacc/hw/tb/run_tb_core.sh build
QBC_TAG=_v2 qc18bacc/hw/tb/run_tb_core.sh run <export_core.py img0> <img1>
QC_TOPO=1 QC_HOOK=$PWD/qc18bacc/impl/hooks/topo_strip.tcl QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" \
    qc18bacc/impl/run.sh all qb_col_cwfp 1.65 qb_col_cwfp_tt_p1.65_topo
QC_PT_HOOK=$PWD/qc18bacc/impl/pt_class.tcl flow/tsmc65/sta/run_pt.sh qb_col_cwfp_tt_p1.65_topo tt
QB_CFG=slice.cfg QB_TOP=qb_col_cwfp QB_SYN=qb_col_cwfp_tt_p1.65_topo QB_PNR_PERIOD=2.0 QB_REPIN=2 QB_RT_LOOPS=0 \
    QB_GR_ADJ=0.15 QB_DR_ITER=8 QB_DR_ARGS='-or_seed 3' qc18bacc/impl/pnr/run.sh pnr qcs2_a   # (try 3: QC_PNR_FROM=cts)
QB_REPIN=2 QB_GR_ADJ=0.15 ... qc18bacc/impl/pnr/run.sh est qcs2_a      # post-GRT estimates (db/cts_drv = cts_rt copy)
```

