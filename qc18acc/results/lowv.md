# QC18-ACC v2 at tt 0.8 V (measured cells, modelled macros)

Netlist `qa2_w3.3` (v2, DC WLM, 3.3 ns at ss), unchanged.  Scripts: `qc18acc/power/lowv.sh` (sta / power on
usask), `lowv_sta.tcl`, `pt_power.tcl` (QC_PT_CORNER / QC_PT_LIB), `macro_dat.py` (escale), `lowv.py` (table).
Raw summaries: `results/lowv/`.

## Macros: not characterisable at 0.8 V

The ARM compilers of the kit (`sram_sp_adv`, `rf_sp_adv` in /CMC/kits/arm_tsmc65gp-nonCmcPsa/aci) ship
characterisation data (`corners/*.db`) only for ff_1p1v_{0c,125c,m40c}, ss_0p9v_{125c,m40c} and tt_1p0v_25c; the
generator can only emit views for these corners.  Hence:
* the macros are linked with their **tt 1.0 V** .db in both PT runs (the timing arcs are not valid at 0.8 V);
* the 0.8 V fmax below is the **logic-only** fmax (paths through a macro excluded), all cells at 0.8 V;
* macro energies are **MODELLED**: datatable access energies x (0.8 / 1.0)^2, macro output-net switching x 0.64,
  macro leakage x k_leak = 0.439 (the logic leakage ratio 0.8 V / 1.0 V of the same netlist; bound: x 0.8).

## Timing, tt 0.8 V 25 C (`tcbn65gplustc0d8_ccs`, WLM WireAreaLowkCon, synthesis SDC, 0.25 ns setup uncertainty)

`results/lowv/sta_tcbn65gplustc0d8_ccs.txt` (3.3 ns analysis clock):

| path set | WNS ns | fmax MHz | worst path |
|---|---|---|---|
| **logic only (no macro pin)** | +0.072 | **309.8** | u_drain/loading_reg -> u_seq/cyc_pload_reg_31_ |
| into a macro (macro setup at 1.0 V) | +0.214 | 324.0 | u_seq/f_lwi_reg_0_ -> act macro A[9] |
| out of a macro (macro CLK->Q at 1.0 V) | +0.480 | 354.6 | weight macro -> u_head/dot2_reg_17_ |

The macro-path numbers use 1.0 V macro arcs and are **not** an 0.8 V claim (a macro at 0.8 V is slower: if its
access time scaled like the logic, x ~1.5 = tt 463 / 310 MHz, the weight-macro -> head path would be about at the
limit of 300 MHz).  Compare tt 1.0 V: 463.3 MHz (power_v2.md); logic delay ratio 0.8 V / 1.0 V ~ 1.50.

## Power, tt 0.8 V vs tt 1.0 V at the same clock

Clock 300 MHz (3.3333 ns = 0.8 V logic fmax 309.8 rounded down), the v2 SDF SAIF of image 0 rescaled to that period
(same toggles per cycle; the SAIF was simulated with tt 1.0 V SDF, so the glitch pattern is the 1.0 V one).
The 1.0 V column is the v2 flow at the same 300 MHz (power_v2.md: 231.0 mW / 92.4 uJ at 400 MHz).

clock 3.3333 ns (300 MHz), SDF SAIF image 0 (159982 cycles, 533.3 us / inference)
k_leak (logic leakage 0.8 V / 1.0 V) = 0.439

| quantity | 1.0 V (tcbn65gplustc_ccs) | 0.8 V (tcbn65gplustc0d8_ccs) | ratio |
|---|---|---|---|
| logic internal mW | 90.38 | 55.74 | 0.617 |
| logic switching mW | 40.05 | 24.83 | 0.620 |
| logic leakage mW | 4.84 | 2.13 | 0.439 |
| logic total mW (PT) | 135.26 | 82.69 | 0.611 |
| macro dynamic mW (datatable + output nets) | 26.33 | 16.85 | 0.640 |
| macro leakage mW | 17.15 | 7.53 | 0.439 |
| **total mW (+dat)** | 178.74 | 107.08 | 0.599 |
| leakage mW (logic + macro) | 21.98 | 9.66 | 0.439 |
| **uJ / inference** | 95.31 | 57.10 | 0.599 |
| leakage share % | 12.3 | 9.0 | |
| pJ / dense-equivalent MAC | 0.1716 | 0.1028 | |

bound with macro leakage x 0.8 (no DIBL reduction): 113.26 mW, 60.40 uJ / inference, leakage share 14.0 %

per block at the low voltage (PT logic; macros modelled as above) mW:
  u_array 61.39 (ref 100.24);  u_ppu 15.67 (ref 25.60);  u_drain 0.90 (ref 1.54);  u_head 0.34 (ref 0.60);  u_xbar 1.70 (ref 2.79);  u_agu 0.65 (ref 1.06);  u_seq 0.61 (ref 1.03);  u_host 0.23 (ref 0.38);

**Result: 0.8 V, 300 MHz: 107.1 mW, 57.1 uJ / inference (macro part modelled), leakage 9.0 %; x 0.60 the energy of
1.0 V (92.4 uJ at 400 MHz, 95.3 uJ at 300 MHz)** at 0.75 x the 1.0 V 400 MHz throughput (latency 533 us vs 400 us).
The 0.8 V logic is measured (PT on the 0.8 V liberty, 61 % of the 1.0 V logic power at equal clock: x 0.62
dynamic, x 0.44 leakage); the macros (24 % of the 0.8 V total) are V^2 / leakage-ratio scaled.

## v3 (Kb = 2, netlist `qa3_w3.3`) at tt 0.8 V

Same method, scripts and labels as v2 above (`QA_V=3` selects the v3 macro set `qa_act_512x64m4` + weight / param /
descriptor macros and writes `results/lowv_v3/`):

```bash
QA_V=3 qc18acc/power/lowv.sh -H tau1 sta qa3_w3.3                                        # 0.8 V STA (~1 min)
QA_V=3 qc18acc/power/lowv.sh -H tau1 power qa3_w3.3 3.3333                               # PTPX 0.8 V + macro model
QA_V=3 qc18acc/power/lowv.sh -H tau1 -l tcbn65gplustc_ccs -v 1.0 power qa3_w3.3 3.3333   # 1.0 V reference, same clock
QA_V=3 python3 qc18acc/power/lowv.py > qc18acc/results/lowv_v3/lowv_3.3333ns.md
```

Netlist `qa3_w3.3` (DC WLM, pre-CTS, ideal clock); SAIF = the v3 tt-SDF GLS SAIF of image 0 (the one of the v3 1.0 V
power run in [v3.md](v3.md)), rescaled to 3.3333 ns, all 371 283 nets annotated from it.  Macros: tt 1.0 V views,
energies MODELLED (datatable x 0.64, output-net switching x 0.64, leakage x k_leak = 0.440, the logic leakage ratio of
this netlist).

Timing, tt 0.8 V 25 C (`results/lowv_v3/sta_tcbn65gplustc0d8_ccs.txt`, 3.3 ns analysis clock) [S]:

| path set | WNS ns | fmax MHz | worst path |
|---|---|---|---|
| **logic only (no macro pin)** | +0.040 | **306.8** | u_xbar/s3_vld_reg -> u_seq/cyc_busy_reg_31_ (32-b busy-cycle counter) |
| into a macro (macro setup at 1.0 V) | +0.226 | 325.3 | u_seq/f_lhi_reg_1_ -> act macro A[8] |
| out of a macro (macro CLK->Q at 1.0 V) | +0.480 | 354.6 | weight macro -> u_head/dot2_reg_16_ |
| hold (all) | +0.022 | | host write staging -> weight macro D |

v2 logic-only: 309.8 MHz (the PE / PPU of v3 are not the 0.8 V limit; the perf counter is).  Clock 300 MHz (3.3333 ns,
the logic fmax rounded down), as v2.

Power at 300 MHz, tt 0.8 V vs tt 1.0 V (`results/lowv_v3/lowv_3.3333ns.md`) [P] + [Mo] macros:

| quantity | 1.0 V | 0.8 V | ratio |
|---|---|---|---|
| logic internal mW | 121.98 | 75.24 | 0.617 |
| logic switching mW | 59.86 | 37.15 | 0.621 |
| logic leakage mW | 6.04 | 2.66 | 0.440 |
| logic total mW (PT) | 187.88 | 115.04 | 0.612 |
| macro dynamic mW (datatable + output nets, MODELLED at 0.8 V) | 54.43 | 34.83 | 0.640 |
| macro leakage mW (MODELLED at 0.8 V) | 15.15 | 6.66 | 0.440 |
| **total mW (+dat)** | 257.46 | **156.53** | 0.608 |
| **uJ / inference** (81 438 cycles, 271.5 us) | 69.89 | **42.49** | 0.608 |
| leakage share % | 8.2 | 6.0 | |
| pJ / dense-equivalent MAC | 0.1258 | 0.0765 | |

Bound with macro leakage x 0.8 (no DIBL reduction): 161.99 mW, 43.97 uJ / inference.  Per block at 0.8 V (PT, mW):
u_array 82.58 (1.0 V: 134.57), u_ppu 24.29 (39.75), u_xbar 3.28 (5.38), u_drain 1.05 (1.77), others < 1.

**Result v3: 0.8 V, 300 MHz: 156.5 mW, 42.5 uJ / inference (macro part modelled), x 0.61 the energy of v3 at 1.0 V
(69.9 uJ at 300 MHz, 68.5 uJ at 400 MHz); vs v2 at 0.8 V / 300 MHz 57.1 uJ: x 0.744** (the v3 / v2 ratio at 1.0 V is
x 0.741), at 3 684 inferences / s (v2 0.8 V: 1 875).  All pre-route (no clock tree, WLM); the post-route penalty of
[pnr_v3.md](pnr_v3.md) applies on top.
