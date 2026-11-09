# QC18-ACC v2 place & route (OpenROAD) — post-route timing, power, GLS

Input: DC netlist `qa2_w3.3` (v2, WLM, 3.3 ns at ss; pre-route PT: ss 303.2 / tt 463.3 MHz, 6.430 mm2, 231.0 mW =
92.4 uJ / inference at 400 MHz tt, [power_v2.md](power_v2.md)).  Tool: OpenROAD 2.0-12381 (Cadence licence refused
for this account), flow `flow/tsmc65/pnr` + design config `qc18acc/pnr/` (`qa.cfg`, `macro_place.tcl`,
`pdn_macro.tcl`, `pins.tcl`, `rows_fix.tcl`, `post_cts.tcl`, `post_grt.tcl`), run on usask
(`qc18acc/pnr/run.sh pnr qa_t1`, settings below; run dir usask:/tmp/ckp908/qc18acc/build/pnr/qa_t1, all kit-derived
views stay there).  Post-route analysis: `run.sh pt` (`pt_post_qa.tcl`), `power.sh` (`saif_flat.py`,
`pt_power_post.tcl`, `macro_dat.py`), `report.py`.  Raw summaries: `results/pnr/`.

**Stage reached: complete** — floorplan, PDN, placement, CTS, global + detailed route (255 residual DRC markers),
SPEF (captable RC, def2spef), PrimeTime ss / tt, PTPX tt with the v2 SAIF, zero-delay GLS (post-CTS PASS; routed see §6).

## 1. Floorplan and PDN

| item | value |
|---|---|
| die | 3156.6 x 2806.2 um = **8.858 mm2** (core 8.734 mm2) |
| macros | 33 fixed, 5.548 mm2: tiers top / bottom: wgt x3 + par (outermost), 3 rows of 4 act banks each side (buf 0 / 1 next to the logic band, buf 2 outer), descriptor RF next to the top act row; all signal-pin edges face the logic band (top R0, bottom MX) |
| spacing | halo 10 um, 20 um between macros in a row, 60 um row channels between macro rows (logic of the act-bank pins), 400 um logic band, 20 um rows between the outer tiers and the core edge (pdngen needs them; placement-blocked) |
| IO | 92 pins on the left edge of the logic band |
| PDN | M1 followpin rails, M4 0.4 / 20 um, M7 **2.0** / 30 um (0.8 um: no M7-M8 via fits), M8 2.0 / 60 um global mesh (the outer tiers have no rows); SRAM rings (VDDCE / VDDPE -> VDD, VSSE -> VSS, M3 / M4) connected by M4 -> M7 via stacks, RF ring (M2 / M3) by macro M4 straps; check_power_grid VDD / VSS: connected |
| cells after P&R | 1.252 mm2 (DC 0.882: +42 %; repair_design on the 32.7k nets with DRV violations, CTS, setup / hold repair); utilisation 0.779 of the core (macros + cells) |

## 2. Placement, CTS, routing

* **Global placement**: the automatic 1024 x 1024 bin grid (3 um bins on this die) diverged (GPL-0307) at overflow
  0.17-0.24 in 7 runs — with / without timing- and routability-driving, density 0.6-0.8, with / without row channels
  or edge blockages; **512 x 512 bins converge** (`GPL_ARGS -bin_grid_count 512`).  Timing-driven placement
  (precedent lesson) still diverged at the second-to-last reweight with 512 bins; stopped early (`-overflow 0.13`)
  it placed (post-place ss -2.01 ns vs -2.49 non-TD) and went through CTS (post-CTS ss -2.41 vs -2.42 ns: no
  gain), but could not be routed in parallel (usask RAM: detailed route 17.8 GB of 30 GB; no server-to-server copy).
  **The routed result is the non-timing-driven placement** (density 0.6, 512 bins).
* **CTS**: `clock_tree_synthesis -balance_levels` (CKBD4-16), 7 319 clock-tree cells (OpenROAD sizes almost all
  as CKBD16), through 1 230 ICGs (1 197 DC + 33 macro CKLNQD2).  Post-route (PT): tt latency up to 1.49 ns, worst
  skew 0.40 ns tt / 0.59 ns ss.
* **Repair**: repair_design on violating nets only; post-CTS and post-GRT repair_timing setup + hold (legalisation
  window 300 um).  IO input / output delays are relative to the ideal clock edge, so the 1.5-3.5 ns propagated
  latency made the host-port inputs hold-violating (fixed with delay) and their setup the worst path: fmax is quoted
  register-to-register.
* **Global route**: no overflow (GR_ADJUST 0.25), 18.0 m wire, 2.47 M vias after detailed route.
* **Detailed route**: 355 743 markers after iteration 0, 36 095 (it. 3), 4 190 (it. 7), 400 (it. 14); plateau, so
  the end iteration was lowered 64 -> 22 in the running process (gdb, `drt::END_ITERATION`), final after 23
  iterations: **255 DRC markers** (143 short, 79 metal spacing, 32 cut short, 1 cut spacing; mostly M1 / VIA1 at
  pins and M2-M7 hot spots).  Peak RSS 17.8 GB, route step 3.4 h.
* **Antennas**: repair_antennas segfaults in this OpenROAD build (AntennaChecker::findWireRoots on global-route
  wires) -> no antenna repair; check_antennas on the routed DB (separate session): **192 net / 192 pin violations**.
* Not covered by the router's DRC (flow README): M1 MINIMUMCUT rules dropped for pin access, LEF57 rules, metal fill.

## 3. Parasitics

`py/def2spef.py` (per-layer R / C from the kit captables, the verified RC model of the flow; no OpenRCX rules for
the kit).  PT annotation: 292 170 of 301 958 nets with RC networks (96.8 %); not annotated: 6 506 pin-to-pin nets,
3 282 driverless.  (OpenROAD's own post-route STA in `summary.txt`, `post_route_*`, is **invalid**: its SPEF reader
stops at the empty `*D_NET SYNOPSYS_UNCONNECTED_*` entries (STA-1657, 300k unannotated drivers); PT reads them.)

## 4. Post-route timing (PrimeTime, SPEF, propagated clock, synthesis SDC)

| corner | reg2reg WNS @3.3 ns | **reg2reg fmax** | incl. host IO | pre-route (DC netlist, WLM) | worst path |
|---|---|---|---|---|---|
| ss 0.9 V 125 C | -2.497 ns | **172.5 MHz** | 142.8 MHz | 303.2 MHz | u_xbar/s3_code_reg -> PE rot2 -> tadd -> acc -> sh_out (PE (4,4)) |
| tt 1.0 V 25 C | -0.169 ns | **288.3 MHz** | 242.7 MHz | 463.3 MHz | same |

Hold after route: tt -0.132 ns (139 endpoints), ss -0.309 ns (126), host-port write data -> weight macro D; not
repaired after detailed route.  The loss vs pre-route: DC sized for WLM wires (D0 / D1 cells now drive routed nets
in the PE adders), clock skew 0.4-0.6 ns, no timing-driven placement / post-route optimisation.

## 5. Post-route power (PTPX, tt 1.0 V, v2 SDF SAIF of image 0 flattened onto the routed netlist, +dat macro model)

Clock **285.7 MHz (3.5 ns)** = post-route tt fmax 288.3 MHz rounded down (the SAIF rescaled to the same toggles per
cycle).  SAIF annotation of the routed netlist: **268 938 of 301 958 nets from the SAIF (89.1 %)**, 10.45 % implied
(propagated through the P&R-inserted buffers / clock tree), 0.48 % default (1 464 nets, constant / tie).

clock 3.5 ns (286 MHz), routed netlist, tt 1.0 V

| quantity | value |
|---|---|
| PT total mW (int / switch / leak) | 253.38 (140.07 / 86.48 / 26.83) |
| **+dat total mW** | **272.20** |
| **uJ / inference (+dat)** | **152.42** (PT only 141.88) |
| leakage share (+dat) | 9.9 % |
| CTS clock-tree cells (n = 7319) mW | 48.23 = 17.7 % of +dat |
| PT clock_network group (CTS buffers + ICGs + register clock pins + clock nets) mW | 84.80 = 31.2 % |
| all ICGs (CKLNQD, n = 1230) mW | 3.71 |
| top-level glue (repair / hold buffers outside the RTL hierarchy, ties) mW | 23.14 |

| block | PT mW | +dat mW | leakage mW |
|---|---|---|---|
| u_array | 113.83 | 113.83 | 4.37 |
| u_ppu | 30.85 | 30.85 | 0.92 |
| u_drain | 3.59 | 3.59 | 0.38 |
| u_head | 0.60 | 0.60 | 0.20 |
| u_xbar | 3.32 | 3.32 | 0.12 |
| u_agu | 1.27 | 1.27 | 0.03 |
| u_seq | 0.96 | 0.96 | 0.08 |
| u_host | 0.37 | 0.37 | 0.07 |
| activation macros | 12.27 | 24.77 | 8.07 |
| weight macros | 9.44 | 15.52 | 6.89 |
| param macros | 2.18 | 2.41 | 2.14 |
| descriptor macro | 0.05 | 0.05 | 0.05 |
| u_act wrapper logic | 2.51 | 2.51 | 0.48 |
| u_wmem wrapper logic | 0.70 | 0.70 | 0.08 |
| u_pmem wrapper logic | 0.06 | 0.06 | 0.02 |
| u_desc wrapper logic | 0.01 | 0.01 | 0.00 |
| CTS clock tree | 48.23 | 48.23 | 0.95 |
| top-level glue | 23.14 | 23.14 | 1.98 |
| **total** | 253.38 | 272.20 | 26.83 |

SAIF annotation: nets from activity file 268938 (89.06 %); line: Nets             268938(89.06%)    0(0.00%)     0(0.00%)     0(0.00%)         0(0.00%)        0(0.00%)        1464(0.48%)     1(0.00%)        31555(10.45%)   0(0.00%)      301958

Same clock as the pre-route numbers (2.5 ns = 400 MHz; the routed design does **not** close it, comparison only):

| quantity | value |
|---|---|
| PT total mW (int / switch / leak) | 344.00 (196.09 / 121.08 / 26.83) |
| **+dat total mW** | **370.35** |
| **uJ / inference (+dat)** | **148.12** (PT only 137.58) |
| leakage share (+dat) | 7.2 % |
| CTS clock-tree cells (n = 7319) mW | 67.15 = 18.1 % of +dat |
| PT clock_network group (CTS buffers + ICGs + register clock pins + clock nets) mW | 118.40 = 32.0 % |
| all ICGs (CKLNQD, n = 1230) mW | 5.18 |
| top-level glue (repair / hold buffers outside the RTL hierarchy, ties) mW | 31.61 |

vs pre-route 231.0 mW / 92.4 uJ at 400 MHz: +139 mW = clock tree 67.2 mW, repair / hold buffers (top glue) 31.6 mW,
routed-wire switching (switching power 121.1 vs 53.5 mW).  **Post-route energy: 152.4 uJ / inference at 286 MHz
(148.1 uJ at 400 MHz), 1.65x the pre-route 92.4 uJ**; clock-tree cells 17.7 % of the total (whole clock network
incl. ICGs and register clock pins 31.2 %).

## 6. Gate-level simulation of the P&R netlists (zero delay, VCS, image 0)

`qc18acc/gls/run_gls.sh start usask <tag>` with the flat OpenROAD netlist (gen_snap.py handles the escaped flat
names; TB `QA_NPASS` define for the flat npass nets).
* post-CTS netlist (`db/cts.odb`, tag qa2_cts): **RESULT PASS** — all logits + 20 stored maps bit-exact, 22 cycle
  counters = RTL (159 982 cycles).
