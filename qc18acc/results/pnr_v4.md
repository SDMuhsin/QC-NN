# QC18-ACC v4 place & route (OpenROAD): distributed-crossbar placement, routed timing / power / GLS, executed TOPS / mm2

Input: DC netlist `qa4_w3.3` (v4, 16 pixel rows, 128 PEs, registered macro boundaries, staged crossbar; WLM, 3.3 ns at
ss; pre-route: 7.764 mm2, 1 601.9 kGE, fmax ss 303.5 / tt 465.5 MHz, 62.68 uJ / inference at 400 MHz tt,
[v4.md](v4.md)).  Tool: OpenROAD 2.0-12381 (no Innovus licence), flow `flow/tsmc65/pnr` (unchanged) + design configs
`qc18acc/pnr/qa4*.cfg`; PrimeTime / PTPX Q-2019.12 with the def2spef SPEF; VCS for GLS.  Hosts usask / tau5
(/tmp/ckp908/qc18acc/build/pnr/<tag>; all kit-derived views stay there), summaries in `results/pnr_v4/`.

Labels: **[M]** measured in simulation (GLS / RTL cycle counters); **[S]** static: routed-design geometry, DRC /
antenna counts, PrimeTime with the def2spef SPEF, or OpenROAD's own estimate where marked "OR est."; **[R]** PrimeTime PX
power of the routed netlist with the gate-level SAIF; **[Mod]** model (macro access energy from the ARM datatables,
"+dat"; op counts from the weight image; derived ratios).

## 0. Summary (route of record `qa4_u9`; hold-fix reruns `qa4_t6` / `qa4_u10` in section 4)

| quantity | v4 routed `qa4_u9` | v4 pre-route ([v4.md](v4.md)) | v3 routed `qa3_t5c` ([pnr_v3.md](pnr_v3.md)) | label |
|---|---|---|---|---|
| die / total area | **12.685 mm2** (3363.8 x 3771.0 um) | 7.764 mm2 | 10.384 mm2 | [S] |
| standard cells after P&R (DC) / core utilisation | 3.951 mm2 (2.307) / 0.76 | | 1.788 mm2 (1.176) / 0.695 | [S] |
| crossbar hub | none (structured placement; band max tile util < 0.95 except 2 tiles) | | 93-100 % hub, 99 % of the markers | [S] |
| detailed route / DRC markers | 25 iterations / **73** | | 9 iterations (stopped) / 70 675 | [S] |
| antenna violations (nets) | **155** | | 137 | [S] |
| **fmax reg2reg ss / tt** (PT + SPEF) | **200.3 / 290.7 MHz** | 303.5 / 465.5 MHz | 148.9 / 272.4 MHz | [S] |
| critical path | `u_seq/f_lwo_reg` -> far act-macro address flop (ss and tt) | PPU partial product (ss) / seq counter (tt) | PPU lane 2 | [S] |
| hold after route tt / ss | **-0.47 / -0.71 ns** (3 500 / 2 827 endpoints, macro D pins; section 4) | | -0.46 / -0.78 ns | [S] |
| power (+dat) / energy per inference | **751.8 mW / 111.46 uJ** at 3.5 ns (285.7 MHz) | 591.8 mW / 62.68 uJ at 400 MHz | 361.0 mW / 108.8 uJ at 3.7 ns | [R] + [Mod] |
| routed-netlist GLS, image 0 | **PASS**, bit-exact, 42 360 cycles = RTL | | PASS | [M] |
| peak / average executed TOPS / mm2 at the routed tt fmax | **0.188 / 0.139** | 0.491 / 0.364 (at 465.5 MHz) | 0.107 / 0.083 (at 272.4 MHz, 10.384 mm2) | [S] + [M] + [Mod] |
| dense-equivalent TOPS / mm2 (secondary) | 0.601 | 1.57 | 0.36 | [S] + [M] + [Mod] |
| area per peak executed MAC / cycle | **3 097 um2** (x1.63 pre-route) | 1 896 um2 | 5 070 um2 | [S] |


## 1. Floorplan (`macro_place4.tcl`, `qa4.cfg`)

| item | value |
|---|---|
| macros | 57 fixed, 5.457 mm2: 48 act `qa_act_256x128m2` (rf_sp_adv, 397.97 x 139.52 um), 6 weight, 2 param, 1 descriptor; tiers as v3 (weight / param outermost, then 3 act rows per side, signal-pin edges facing the band), halo 10 um, 60-um channels between macro rows |
| v4 change | a bank's three buffers stack in one **column** (v3: one row = one buffer), so the 3:1 bank-select register of the distributed crossbar sits under its own column; the 16 banks form a **ring** (top banks 0-7 left to right, bottom 15-8), so every stage-A source set (banks i..i+3 mod 16) is a contiguous arc |
| logic band | 1 600 um (v3 950): v4 logic is 1.96x v3 (1 601.9 vs 816.4 kGE) |
| die | **3363.8 x 3771.0 um = 12.685 mm2** [S] (v3 10.384 mm2) |
| PDN, IO | as v3 (M1 rails, M4 / M7 / M8 straps, RF macro grid now also for the act banks `pdn_macro.tcl`; 95 IO pins on the left band edge) |
| flow settings | the v3 improved recipe (`qa3b.cfg`): gpl 512 x 512 bins, density 0.6, CTS `-balance_levels -sink_clustering_buffer CKBD4`, host IO relative to the propagated host-register clock, post-GRT +0.2 ns macro hold margin, no antenna repair |
| route step | `route_split.tcl`: global route + post-GRT repair, then detailed route in a fresh process without liberty / STA, fillers after detailed route (memory: v3's single route process peaked at 25.2 GB of 30 GB with 422 k nets; v4 has 717 k) |

## 2. Does a hub form again?  Placement study (band 1 600 um unless noted) [S, OR est.]

Checked before any detailed route, with `gr_diag.tcl` (cell utilisation per 50-um tile, fillers excluded) and the
global-route guides (`guide_density.py`: per tile, guide length on a layer / track capacity of the tile, the
relative indicator of [pnr_v3.md](pnr_v3.md) 11.2), calibrated on v2 `qa_t1b` (converged, 251 markers) and v3
`qa3_t5b` (70 584 markers in the hub):

| run | change | place WNS ss / tt (ns) | band tiles > 0.95 util | M2 guide ratio p90 / tiles > 1.3 | outcome |
|---|---|---|---|---|---|
| v2 `qa_t1b` (reference) | | | | 0.98 / 0.7 % | routed, 251 DRC |
| v3 `qa3_t5b` (reference) | | | 29 of 55 hub tiles | 1.16 / 3.7 % (hub mean 1.11) | 70 584 DRC |
| `qa4_u1` | `qa4.cfg` | -17.93 / -7.74 | 44 of 1 772, xbar hub at x 1.35-1.70, y 1.70-2.10 mm | 1.19 / 4.0 % (hub mean 1.13) | **the hub forms again** |
| `qa4_t2` | + routability-driven gpl | -17.93 / -7.74 | (identical placement) | | gpl's RC check (1.15) did not change the result |
| `qa4_u2` | `qa4b.cfg`: structured crossbar placement | -14.26 / -5.84 | 164, in strips along both band edges | | hub gone; pile-up at the macro edges |
| `qa4_t3` | + channels max density 30 % | -11.84 / -4.38 | 199 (cells outside the band 8.5 -> 3.2 %) | | |
| `qa4_t4` | + band edges max density 50 % (120 um) | -3.24 / -0.77 | 105, around the window registers | 1.17 / 3.1 % | post-GRT hold repair > 1.5 h (11 349 endpoints), stopped |
| `qa4_u5` | t4 + gpl overflow 0.05 | -2.86 / -0.80 | 106 | | same pile-ups |
| `qa4_u6` | t4 + density 0.78 | -5.48 / -1.51 | 329 | | denser |
| `qa4_u7` | t4 + incremental gpl after the DRV repair | -9.14 / -3.56 | 0 (max < 0.85) | | repair buffers left off their wires |
| `qa4_u8` | u7 + DRV repair again | -2.00 / -0.32 | 1 (61 > 0.85) | | 349 cells in the blocked edge-row strips: TritonCTS looped (> 40 min on one clock net) |
| **`qa4_u9`** | u8 + rows inside hard blockages removed after the incremental pass | -2.03 / -0.33 | 2 (58 > 0.85; mean 0.67; cells outside the band 4.8 %) | 1.12 / 2.1 % (M3 p90 0.80) | routed, 24 iterations (section 3) |
| **`qa4_t6`** | **`qa4c.cfg`**: u9 + macro clock gates next to their macros (section 4) | -2.11 / -0.43 | | | detailed route running at the time of writing |
| `qa4_t5` | u9 settings, band 1 800 um (die 13.357 mm2) | -1.68 / -0.06 | | 1.10 / 2.2 % | detailed route stopped after iteration 3 (diagnosis, section 3) |

Mechanisms, in order of discovery:

1. **The hub forms again with the v3 recipe (`qa4_u1`).**  Centroids of the crossbar register groups (`locs.tcl` /
   `locs.py`): all 16 x 128 bank-select registers (`u_act/ar_rdata`), the 16 stage-A (`u_xbar/sa`) and the 16 window
   (`u_xbar/win`) groups land within ~350 x 400 um at the band centre (x 1.42-1.92 mm, y 1.58-2.23 mm), and the
   per-macro output registers follow into the macro-row channels at x 1.0-2.3 mm (bank 0's macro is at x 0.2 mm: its
   128-b Q bus runs ~1.2 mm along a 40-um channel).  A register pipeline is a chain of 2-pin nets whose total length
   does not depend on where along the path each stage sits, so only the density term spreads it, and it loses
   against the connectivity of the 16-way fan-in / fan-out - the distributed RTL alone does not distribute the
   placement.  The GRT guide indicator of the hub (M2 mean 1.13, p90 1.19) equals v3's failing hub (1.11 / 1.16).
2. **Structured placement (`xbar_place.tcl`).**  The 6 144 stage registers are placed FIRM before global placement:
   bank-select k under its bank column at the band edge, stage-A slot i at the centroid of its source banks
   i..i+3 (40 um into the band), window row j on an 8 x 2 grid over the PE area (shadow chain A rows in the lower,
   chain B in the upper half); they are released (PLACED) right after global placement so the DRV repair and
   legalisation can resize / move them (left FIRM, the resized flops overlapped: DPL-0033).  The PEs of row j then
   cluster around window j (each PE row is one ~250 x 600 um region), the hub disappears.
3. **Pile-ups at the band edges and in the channels (`qa4_u2`, `qa4_t3`).**  The residual overflow went to the
   band edges (cells pressed against the act-macro rows, 50-150 um deep, at 95-100 % over the whole width: PE
   cells, 5 565 long-wire buffers, act-port logic) and into the channels (the head's `pfd` / `prod` / `fifo`
   registers at y 2.58-3.04 mm, strung over ~0.5 mm: the `qa4_u1` post-CTS tt path `u_head/pfd -> prod` was -3.6 ns
   with D0 / D1 cells driving 0.05-0.18 pF).  Partial placement blockages (`ch_block.tcl`, max density 30 % in the
   channels, 50 % over the 120 um of band next to each act tier; global placement honours them: cells outside the
   band 8.5 -> 3.2 %) clear both and take the placement setup from -14.3 / -5.8 to -3.2 / -0.8 ns (ss / tt).
4. **The remaining pile-ups come from the DRV repair, not from global placement (`qa4_t4`, `qa4_u5`, `qa4_u6`).**
   Global placement runs at 51.6 % utilisation of the free area (padded cells) against the target density 0.6;
   the DRV repair that follows inserts ~67 k buffers and resizes ~116 k cells (+40 % cell area, padded 72.7 %, so the
   target 0.6 becomes infeasible: GPL-0302), and detailed placement can only legalise in place, so the PE-row
   clusters around the window registers end at 95-100 %.  A tighter gpl overflow (0.05) leaves the same 106 tiles;
   a higher target density (0.78) makes 329.  **Incremental global placement after the repair** at density 0.76,
   then a second DRV repair of the nets the move broke (34.6 k buffers), gives a uniform band (mean 0.67, 1 tile
   > 0.95) with better timing (place -2.00 / -0.32 ns).
5. **Incremental gpl ignores hard placement blockages (`qa4_u8`).**  349 cells landed in the 20-um row strips outside
   the weight tiers (hard-blocked by `rows_fix.tcl`); one of them was a clock sink of `u_wmem_o`, and TritonCTS
   looped on that net's H-tree (no progress for > 40 min).  The rows inside hard blockages are now removed after
   the incremental pass (the PDN is already built), so the legaliser moves those cells out (`qa4_u9`).

## 3. Detailed route: converges (`qa4_u9`) [S]

`route_split.tcl` (global route + post-GRT repair in one process: 52 min, 13.8 GB peak; detailed route in a fresh
process without liberty / STA, fillers after it).  Detailed-route memory: 8.0 GB after pin access, 21.9 GB after
track assignment, 25.5 GB peak RSS (of 30 GB, a few GB of swap), 861 821 nets, 786 513 instances without fillers;
25 iterations in 7 h 36 min.

| iteration | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 12 | 14 | 16 | 18 | 20 | 22 | 24 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `qa4_u9` markers | 1 102 127 | 417 968 | 393 236 | 130 734 | 46 807 | 18 135 | 8 180 | 4 298 | 2 783 | 1 617 | 658 | 319 | 231 | 188 | 137 | 94 | 82 | **73** |
| `qa4_t5` (band 1 800) | 1 130 558 | 439 274 | 412 512 | 141 953 | stopped | | | | | | | | | | | | | |
| v3 `qa3_t5c` (hub) | 648 053 | 273 247 | 259 410 | 141 244 | 99 837 | 84 828 | 77 062 | 73 622 | 70 675 (stopped) | | | | | | | | | |

* **Result: 73 DRC markers** (M2 short 20, M2 spacing 17, M1 short 15, VIA1 cut spacing 10, VIA1 cut short 8, M1
  spacing 3); 62 of them at the pin edges of the four top-tier weight / param macros (shorts of hold / repair-buffer
  nets with the macro obstruction at y 3 315.6 um, ~14-20 per macro), 11 inside PEs.  Wire 48.8 m.  v2 ended at 251-255,
  v3 did not converge (70 675, 99 % in the hub).
* **Mechanism of the convergence (vs v3):** after iteration 3 the markers of `qa4_t5` (stopped there for the
  diagnosis, `drc_map.py`) were spread over the whole band (top 50 of 561 occupied 100-um tiles hold 31 %; v3: one
  hub with 99 %), 80 % of them on PE nets (M2 shorts: pin access in the dense PE logic, 77 k markers per mm2 of PE cells vs
  34 k for the PPU), i.e. ordinary unfinished search-and-repair, not a structural hotspot.  From iteration 3 on the
  count fell by 55-65 % per iteration down to ~1 600 (v3: -4 % per iteration from 85 k), then by 15-40 % per
  iteration.  The band width barely matters: `qa4_t5` (band 1 800, 0.60 utilisation) had 3-8 % *more* markers than
  `qa4_u9` (1 600, 0.67) at iterations 0-3.
* **Antennas** (check_antennas on the routed DB, separate session; repair_antennas segfaults in this build):
  **155 nets / 155 pins** (v3 137, v2 147-192).

## 4. Hold at the macro pins: the pre-route repair is not enough [S]

The netlist SDC's 0.4-ns min delay on the weight / param pins and the post-GRT hold repair (+0.2 ns on the weight /
param macro CLK pins) gave **hold met at the GRT estimate** (`grt_opt` ss / tt +0.017 / +0.021 ns), but PrimeTime with
the routed SPEF finds (`qa4_u9`): **tt -0.47 ns (3 500 endpoints), ss -0.71 ns (2 827)**; 92 % of them act-macro D
pins (tt 3 233), the rest weight / param / descriptor macro D pins and a few PPU registers.  Two mechanisms
(full-clock path reports `rpt/pt_post_<c>_min_clk.rpt`, OpenROAD vs PT on the same path):

1. **Macro clock gates far from their macros.**  Each macro CLK is driven by its own CKLNQD2 (`g_mac_u_cg`) through a
   1-sink net that CTS does not buffer.  In `qa4_t5` the gate of `u_wmem_o` bank 2 sat far from the macro (in the
   blocked row strip under the tier, ~0.97 mm Manhattan): 0.25 pF on the gated net, 0.78-0.93 ns slew, macro CLK at 2.24 ns vs 1.25 ns at
   its input flops (tt; ss 2.88 vs 1.84) - the v3 "late weight-macro clock" again, larger.  Fix (`macro_icg.tcl`,
   `qa4c.cfg` `QA_MACRO_ICG CKLNQD16`): all 57 macro gates resized to CKLNQD16 and placed at their macro's CLK pin
   before CTS (that weight gate: ~0.97 mm -> 46 um from its pin).  Run `qa4_t6` (routing at the time of writing).
2. **OpenROAD's pre-route clock latency estimate is off by ~0.4 ns at the leaves.**  Worst act-macro D path
   (`u_act/g_bank_7__wd_q_reg_64_` -> bank 7 buffer 0 macro D[64], tt): PT + SPEF launch clock 1.36 ns, macro CLK
   1.52 ns, no hold buffer, slack -0.22 ns; OpenROAD on the same placement (estimated parasitics) launch clock
   1.757 ns, macro CLK 1.470 ns, slack +0.243 ns.  The repair therefore saw no violation.  A margin that covers
   the estimate error on all macro CLK pins (`QA_MACRO_HOLD 0.3`, `QA_MACRO_HOLD_RE .`) plus the gate fix is run
   `qa4_u10` (in CTS at the time of writing).
A post-route ECO in this OpenROAD build would re-route the whole design (`hold_eco.tcl`, ~7.5 h) and could not be
timed with the SPEF (OpenROAD's SPEF reader stops at the netlist's empty `SYNOPSYS_UNCONNECTED` nets, results/pnr.md).

## 5. Post-route timing (PrimeTime, def2spef SPEF, propagated clock, `QA_IO_REF=1`) [S]

fmax = 1 / (3.3 ns - WNS); reg2reg excludes the host-port IO.

| run | corner | reg2reg WNS | **fmax** | logic-only fmax | worst path | hold WNS (endpoints) |
|---|---|---|---|---|---|---|
| **`qa4_u9`** (73 DRC) | ss 0.9 V 125 C | -1.694 | **200.3 MHz** | 200.3 | `u_seq/f_lwo_reg_2_` -> `u_act/g_bank_13__g_buf_1__addr_q_reg_0_` (AGU / seq request -> act-macro address flop, ~1.2 mm) | -0.710 (2 827) |
| **`qa4_u9`** | tt 1.0 V 25 C | -0.140 | **290.7 MHz** | 290.7 | same | -0.471 (3 500) |
| `qa4_t5` (iteration 3) | ss | -1.692 | 200.3 | 200.3 | `u_wmem_e/sel3_reg_1_` -> `u_head/prod_reg_4__15_` | -0.415 (1 912) |
| `qa4_t5` (iteration 3) | tt | -0.042 | 299.2 | 299.2 | `u_seq/f_lwo_reg_2_` -> act bank 15 address flop | -0.327 (2 400) |
Pre-route (DC netlist, WLM, ideal clock): ss 303.5 / tt 465.5 MHz; routed tt / pre-route tt = x0.62 (v3 improved
x0.64, v2 x0.62).  SPEF annotation: 843 674 of 863 049 nets with RC networks (97.8 %).  Clock: worst latency tt 1.89 ns
(weight macro CLK), worst skew 0.53 ns tt (param macro CLK vs its output register).  Neither path is a crossbar path:
the routed critical paths are the long request wires from the central sequencer / AGU to the act-macro input flops
of the far banks (ss and tt) and, in `qa4_t5`, the weight -> head FC multiply (both cross ~1-1.5 mm in one cycle;
the registered boundary moved the flops to the macros, so the AGU -> flop wire became the single-cycle hop).

## 6. Post-route power (PTPX tt 1.0 V, SDF SAIF of image 0 flattened onto the routed netlist, +dat) [R] + [Mod]

`power.sh -t qa4_u9 3.5` (clock = routed tt fmax rounded down to 0.1 ns of period: 3.5 ns = 285.7 MHz; the SAIF
rescaled to the same toggles per cycle; act-macro writes from the program, 41 984 per image, as v4.md 9).

| quantity | `qa4_u9` 3.5 ns | pre-route 2.5 ns (v4.md) |
|---|---|---|
| PT total mW (int / switch / leak) | 701.64 (388.76 / 263.47 / 49.41) | 520.22 (336.85 / 155.85 / 27.52) |
| **+dat total mW** | **751.82** | 591.85 |
| **uJ / inference (+dat)** | **111.46** (PT only 104.03) | 62.68 |
| routed / pre-route energy | **x1.78** | |
| leakage share | 6.6 % | 4.6 % |
| CTS clock-tree cells (n = 35 458) | 115.38 mW = 15.3 % | (ideal clock) |
| PT clock_network group | 189.50 mW = 25.2 % | 154.70 |
| top-level glue (repair / hold buffers, ties; n = 111 k) | 106.17 mW = 14.1 % | |
| PE array / PPU / xbar | 303.41 / 89.30 / 27.16 mW | 340.29 / 103.63 / (in 23.14) |
| act / weight / param macros (+dat) | 51.35 / 23.26 / 3.17 mW | 68.43 / 29.26 / 3.56 |
| SAIF annotation | 83.2 % of 863 049 nets (16.8 % P&R-inserted nets, activity propagated) | |
| inferences / s at 285.7 MHz | 6 745 [M] cycles | 9 443 at 400 MHz |
| executed ops / J | 2.31 TOPS / W [Mod] | 4.10 |

Full tables `results/pnr_v4/qa4_u9_post_3.5ns*` (`report.py 3.5 qa4_u9`).  Where the x1.78 comes from (per
inference, 3.5 vs 2.5 ns): the clock tree (+17.1 uJ, absent pre-route), the P&R glue (+15.7 uJ: ~101 k DRV-repair
buffers of the two place-step repairs and 24.1 k hold buffers of the post-CTS / post-GRT repairs), the leakage of the longer cycle (+4.4 uJ), the routed wires in
the PE array / PPU (switching 263 vs 156 mW in total), partly offset by the lower macro read power per cycle.
v3 routed: 107.6 uJ (x1.57); v4 routed 111.5 uJ is x1.04 of v3 routed at x1.92 its throughput per cycle (42 360 vs 81 438 cycles).

## 7. Gate-level simulation of the routed netlist (zero delay, VCS, image 0) [M]

`QA_V=4 qc18acc/gls/run_gls.sh start usask qa4_u9_pnr 0 1` with `build/syn/qa4_u9_pnr/qa_top.v` = the routed `out/qa_top.v`
(flat; clock tree, repair / hold buffers, decaps): **RESULT PASS**, all 10 logits + 20 stored maps bit-exact, 22 cycle
counters = RTL, **42 360 cycles**.  `qa4_t5` (iteration-3 routing): PASS, 42 360 cycles.

## 8. Executed TOPS / mm2 on the routed die, area per executed MAC [S] + [M] + [Mod]

Die **12.685 mm2** (3363.8 x 3771.0 um, [S]); peak = 128 PEs x 2 blocks x 16 MACs x 2 ops x f = 8 192 ops x f; workload
average = 128 546 560 executed MACs / image x 2 x images / s (images / s = f / 42 360 cycles [M]; MAC count [Mod],
v4.md 7); dense-equivalent (secondary) = 555.4 M MACs / image x 2 x images / s.

| clock | f | images / s | **peak executed TOPS** | **per mm2** | **average executed TOPS** | **per mm2** | dense-eq. TOPS (secondary) | per mm2 |
|---|---|---|---|---|---|---|---|---|
| routed tt fmax (`qa4_u9`) | 290.7 MHz [S] | 6 863 | 2.381 | **0.188** | 1.764 | **0.139** | 7.62 | 0.601 |
| power clock | 285.7 MHz | 6 745 | 2.341 | 0.185 | 1.734 | 0.137 | 7.49 | 0.591 |
| routed ss fmax | 200.3 MHz [S] | 4 729 | 1.641 | 0.129 | 1.216 | 0.096 | 5.25 | 0.414 |
| 400 MHz (pre-route energy clock; not met routed) | 400 MHz | 9 443 | 3.277 | 0.258 | 2.428 | 0.191 | 10.49 | 0.827 |
| pre-route reference (v4.md, 7.764 mm2, 400 MHz) | | | 3.277 | 0.422 | 2.428 | 0.313 | 10.49 | 1.35 |

**Area per peak executed MAC / cycle: 12.685 mm2 / 4 096 = 3 097 um2, x1.63 the pre-route 1 896 um2** [S]
(macros 1 346 um2 of it unchanged; the rest is the band, channels and edges: cells after P&R 3.95 mm2 = 1.71x the
DC logic area, placed at ~0.67 utilisation).  With the tt clock at x0.62 of pre-route, routed peak executed TOPS /
mm2 is 0.188 vs 0.491 pre-route at the pre-route tt fmax (x0.38); the 1.5 executed TOPS / mm2 target is 8x away.

## 9. Open issues

* **Hold after route** (section 4): `qa4_u9` fails hold at the macro inputs by up to -0.47 ns tt / -0.71 ns ss;
  the reruns `qa4_t6` (gates at the macros) and `qa4_u10` (+ 0.3 ns margin on all macros) were still routing.
* The routed design misses the ARCH target tt >= 400 MHz (290.7 MHz): the AGU / sequencer -> far act-macro request
  wires (single-cycle ~1.2 mm hops) and the weight -> head FC path limit it; a register stage on the request path (or
  replicated AGU slices per bank group) would be the RTL fix.
* 73 residual DRC markers (62 at the pin edges of the top weight / param macros), 155 antenna nets (no antenna repair
  in this build); M1 MINIMUMCUT / LEF57 rules not checked, no metal fill; geometric SPEF (captable RC, no coupling).
* Power: 16.8 % of the routed nets (P&R-inserted) carry propagated, not simulated, activity.

## 10. Commands

```bash
# on the P&R host, in /tmp/$USER/qc18acc/repo (synthesis qa4_w3.3 under $QC_BUILD/syn, macros in QC_MC_OUT):
QA_CFG=qc18acc/pnr/qa4c.cfg QC_PNR_TO=cts qc18acc/pnr/run.sh pnr qa4_t6          # floorplan .. CTS (route-of-record recipe)
QA_CFG=qc18acc/pnr/qa4c.cfg qc18acc/pnr/run.sh route qa4_t6                     # GRT + repair, detailed route (no STA), finish, SPEF
QA_V=4 QA_IO_REF=1 qc18acc/pnr/run.sh pt qa4_t6                                 # PrimeTime ss / tt with SPEF
QC_FLOW=$PWD/flow/tsmc65 QC_PNR_OUT=$QC_BUILD/pnr/qa4_t6 QC_BUILD=$QC_BUILD openroad -exit qc18acc/pnr/ant_check.tcl > ant.out
python3 qc18acc/pnr/drc_map.py $QC_BUILD/pnr/qa4_t6/rpt/drt.drc.rpt 100          # marker map / net classes
# diagnostics of section 2 (any checkpoint):
QA_STEP=place QA_NO_GRT=1 QA_WIN="0 400 3400 3400" QC_FLOW=... QC_PNR_OUT=<run> openroad -exit qc18acc/pnr/gr_diag.tcl > g.out; python3 qc18acc/pnr/tilemap.py g.out
QA_STEP=place QA_OUTF=locs.txt QA_RE='^(u_act/|u_xbar/(sa|win)_reg)' QC_PNR_OUT=<run> openroad -exit qc18acc/pnr/locs.tcl; python3 qc18acc/pnr/locs.py locs.txt
python3 qc18acc/pnr/guide_density.py <run>/route.guide 2000 50 0 1090 3400 2680
# locally:
QA_V=4 qc18acc/pnr/power.sh -H usask -t qa4_t6 <period_ns> && QA_V=4 python3 qc18acc/pnr/report.py <period_ns> qa4_t6
ssh <host> 'B=/tmp/$USER/qc18acc/build; mkdir -p $B/syn/qa4_t6_pnr && cp $B/pnr/qa4_t6/out/qa_top.v $B/syn/qa4_t6_pnr/'
QA_V=4 qc18acc/gls/run_gls.sh start <host> qa4_t6_pnr 0 1; QA_V=4 qc18acc/gls/run_gls.sh check <host> qa4_t6_pnr
```

