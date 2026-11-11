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

@@SUMMARY@@

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
| **`qa4_u9`** | **`qa4c.cfg`**: u8 + rows inside hard blockages removed after the incremental pass | -2.03 / -0.33 | @@U9TILES@@ | @@U9GUIDE@@ | **route of record** |
| `qa4_t5` | `qa4c.cfg` settings, band 1 800 um (die 13.357 mm2) | -1.68 / -0.06 | | 1.10 / 2.2 % | hedge (@@T5STATUS@@) |

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

@@ROUTE@@
