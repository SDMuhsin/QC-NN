# QC18-ACC: timing-annotated gate-level simulation and PrimeTime PX power (netlist `qa_w3.3`)

Netlist `qa_w3.3` (DC W-2024.09, tcbn65gplus, kit WLM WireAreaLowkCon enclosed, 3.3 ns at ss; tt fmax 463 MHz,
pre-CTS).  Workload: one full inference (s8kd, test image 0), START..DONE, 159 982 cycles.

## 1. Timing-annotated GLS (tt SDF, 2.5 ns = 400 MHz)

`qc18acc/gls/run_gls.sh sdf usask qa_w3.3`: DC `write_sdf` at tt (tt lib + macro tt .db, synthesis WLM; STA setup
slack +1.14 ns at 3.3 ns, hold -0.08 ns on host-staging -> weight-macro D pins), then `flow/tsmc65/sim/sdf_idealclk.py`
(ideal clock: IOPATHs of the 1194 CKLNQD ICGs zeroed = the whole pre-CTS clock network; ideal reset tree, 15 buffers;
0.5 ns input delay on the 71 host-port INTERCONNECTs = 20 % of the TB clock, the SDC IO rule).
`QA_SDF=1 qc18acc/gls/run_gls.sh start usask qa_w3.3 0 1`: VCS `-sdf typ:qa_tb.dut:<sdf>`, cell and ARM macro specify
blocks and timing checks on, `+no_notifier` (violations would be printed, not X-propagated), the full network.

| | result |
|---|---|
| outputs | RESULT PASS: all 10 logits and all 20 stored maps of image 0 bit-exact |
| cycles | 159 982 START..DONE, every per-pass counter equal to RTL (22 counters, 0 differ); array busy 85.2 %, stall 20 690, param load 4 800 |
| timing checks | 0 violations reported (VCS clamps the cells' negative SDF setup / hold limits to 0: no `+neg_tchk`) |
| SAIF | whole DUT over START..DONE (159 985 TB cycles), `usask:/tmp/ckp908/qc18acc/gls/qa_w3.3/qa_top_img0_sdf.saif` |
| run time | 58 min wall (3 474 s CPU) for program load + image 0 on tau-02 (zero delay: ~11 min / image); full image, no windows |

## 2. PrimeTime PX power (tt 1.0 V 25 C, synthesis WLM, ideal clock)

`qc18acc/power/power.sh [-p 2.5|3.3] qa_w3.3 sdf|zd` -> `results/power/<mode>_<p>ns{,_blocks,_macros}.txt`;
`python3 qc18acc/power/energy.py` -> the tables below.  Averaged mode, 100 % of the nets annotated from the SAIF.

**Macro energy caveat (+dat columns).**  The ARM liberty views of all four macros (sram_sp_adv / rf_sp_adv,
`flow/tsmc65/sram/mc_gen.sh`) have every CLK `internal_power` table at 0; PrimeTime therefore only sees the pin
energies (A, D, CEN, WEN, Q) and misses the access and the deselected-clock energy.  The datatable of each macro
(`<macro>.dat`, same generator run) gives them: tt, EMA 000, E = (icc_c + icc_p) x V.  `macro_dat.py` combines
them with the SAIF activity of each instance (CLK edges, P(CEN = 1), P(WEN = 1)) and the "+dat" columns replace
the macros' PT internal power by this model (macro leakage, which matches the datatable standby current, and the
macro output-net switching stay as PT).  **+dat is the number to use**; PT-only underestimates the macro dynamic power ~16x (7.3 vs 117 mW).
The macro CLK pins are not gated (`clk` straight to every macro), so each deselected macro still burns E_desel
per cycle: 60.5 mW of the 308 mW (gating the macro clocks with CEN would remove most of it).

Clock network: pre-CTS netlist, ideal clock, no clock-tree buffers; PT's clock_network group = the 1194 ICGs, the
clock-pin internal power of the 35 125 registers and the clock-net switching (contained in the blocks).
3.3 ns: same SAIF rescaled (`saif_scale.py`: state times x 1.32, toggle counts kept = the same toggles per cycle).

| SAIF | clock | PT total mW | int / switch / leak mW | +dat total mW | leakage share (+dat) | uJ / inference PT / +dat | pJ / dense MAC (+dat) | pJ / QC add (+dat) |
|---|---|---|---|---|---|---|---|---|
| sdf | 2.5 ns (400 MHz) | 198.59 | 122.82 / 53.97 / 21.80 | 308.35 | 11.0 % (7.1 %) | 79.43 / 123.33 | 0.2220 | 0.969 |
| sdf | 3.3 ns (303 MHz) | 155.73 | 93.05 / 40.88 / 21.80 | 238.89 | 14.0 % (9.1 %) | 82.22 / 126.12 | 0.2271 | 0.991 |
| zd | 2.5 ns (400 MHz) | 153.47 | 90.16 / 41.51 / 21.80 | 264.04 | 14.2 % (8.3 %) | 61.38 / 105.61 | 0.1901 | 0.830 |
| zd | 3.3 ns (303 MHz) | 121.55 | 68.30 / 31.45 / 21.80 | 205.32 | 17.9 % (10.6 %) | 64.17 / 108.40 | 0.1952 | 0.852 |


sdf SAIF, 2.5 ns: blocks (PT total; +dat: macro internal power from the datatable model)

| block | PT mW | % PT | +dat mW | % +dat | leakage mW |
|---|---|---|---|---|---|
| PE array (u_array) | 127.26 | 64.1 | 127.26 | 41.3 | 3.08 |
| PPU (u_ppu) | 34.81 | 17.5 | 34.81 | 11.3 | 0.78 |
| drain (u_drain) | 1.98 | 1.0 | 1.98 | 0.6 | 0.23 |
| head (u_head) | 0.79 | 0.4 | 0.79 | 0.3 | 0.17 |
| AGU + xbar + seq + host + top glue | 6.96 | 3.5 | 6.96 | 2.3 | 0.18 |
| act buffer logic (hold regs, port muxes) | 1.69 | 0.8 | 1.69 | 0.5 | 0.15 |
| weight / param / desc wrapper logic | 0.61 | 0.3 | 0.61 | 0.2 | 0.06 |
| activation macros (24 x 1024x64) | 12.44 | 6.3 | 84.75 | 27.5 | 8.07 |
| weight macros (6 x 4096x80) | 9.81 | 4.9 | 39.09 | 12.7 | 6.89 |
| param macros (2 x 4096x72) | 2.18 | 1.1 | 10.03 | 3.3 | 2.14 |
| descriptor macro (256x32) | 0.06 | 0.0 | 0.40 | 0.1 | 0.05 |
| **total** | 198.59 | 100 | 308.35 | 100 | 21.80 |

PT power groups (cross-cutting; mW total): clock_network 60.90 (ICGs + register clock pins + clock nets, ideal clock, no CTS buffers; internal 51.30, switching 9.58), register 13.70, combinational 99.50, memory 24.50.

macro datatable model (per cycle, all instances of a type):

| macro | reads / cycle | writes / cycle | deselected clocks / cycle | E read / write / desel pJ | P read / write / desel mW |
|---|---|---|---|---|---|
| qa_par_4096x72m8 (x2) | 0.030 | 0.000 | 1.970 | 31.3 / 34.7 / 9.53 | 0.38 / 0.00 / 7.51 |
| qa_act_1024x64m8 (x24) | 6.160 | 0.517 | 17.323 | 16.1 / 22.8 / 4.64 | 39.77 / 4.72 / 32.14 |
| qa_dsc_256x32m2 (x1) | 0.001 | 0.000 | 0.999 | 7.3 / 10.4 / 0.86 | 0.00 / 0.00 / 0.34 |
| qa_wgt_4096x80m8 (x6) | 0.856 | 0.000 | 5.144 | 34.1 / 37.9 / 9.95 | 11.68 / 0.00 / 20.48 |

zd SAIF, 2.5 ns: blocks (PT total; +dat: macro internal power from the datatable model)

| block | PT mW | % PT | +dat mW | % +dat | leakage mW |
|---|---|---|---|---|---|
| PE array (u_array) | 92.35 | 60.2 | 92.35 | 35.0 | 3.08 |
| PPU (u_ppu) | 25.84 | 16.8 | 25.84 | 9.8 | 0.78 |
| drain (u_drain) | 1.81 | 1.2 | 1.81 | 0.7 | 0.23 |
| head (u_head) | 0.78 | 0.5 | 0.78 | 0.3 | 0.17 |
| AGU + xbar + seq + host + top glue | 6.68 | 4.4 | 6.68 | 2.5 | 0.18 |
| act buffer logic (hold regs, port muxes) | 1.65 | 1.1 | 1.65 | 0.6 | 0.15 |
| weight / param / desc wrapper logic | 0.61 | 0.4 | 0.61 | 0.2 | 0.06 |
| activation macros (24 x 1024x64) | 11.69 | 7.6 | 84.80 | 32.1 | 8.07 |
| weight macros (6 x 4096x80) | 9.81 | 6.4 | 39.09 | 14.8 | 6.89 |
| param macros (2 x 4096x72) | 2.18 | 1.4 | 10.03 | 3.8 | 2.14 |
| descriptor macro (256x32) | 0.06 | 0.0 | 0.40 | 0.2 | 0.05 |
| **total** | 153.47 | 100 | 264.04 | 100 | 21.80 |

PT power groups (cross-cutting; mW total): clock_network 60.90 (ICGs + register clock pins + clock nets, ideal clock, no CTS buffers; internal 51.30, switching 9.58), register 8.01, combinational 60.80, memory 23.70.

macro datatable model (per cycle, all instances of a type):

| macro | reads / cycle | writes / cycle | deselected clocks / cycle | E read / write / desel pJ | P read / write / desel mW |
|---|---|---|---|---|---|
| qa_par_4096x72m8 (x2) | 0.030 | 0.000 | 1.970 | 31.3 / 34.7 / 9.53 | 0.38 / 0.00 / 7.51 |
| qa_act_1024x64m8 (x24) | 6.160 | 0.525 | 17.315 | 16.1 / 22.8 / 4.64 | 39.77 / 4.79 / 32.12 |
| qa_dsc_256x32m2 (x1) | 0.001 | 0.000 | 0.999 | 7.3 / 10.4 / 0.86 | 0.00 / 0.00 / 0.34 |
| qa_wgt_4096x80m8 (x6) | 0.856 | 0.000 | 5.144 | 34.1 / 37.9 / 9.95 | 11.68 / 0.00 / 20.48 |

Glitch factor SDF / zd (PT dynamic power, 2.5 ns): design 1.343; per block:
  PE array (u_array) 1.391;  PPU (u_ppu) 1.358;  drain (u_drain) 1.113;  head (u_head) 1.003;  AGU + xbar + seq + host + top glue 1.042;  act buffer logic (hold regs, port muxes) 1.026;  weight / param / desc wrapper logic 1.000;  activation macros (24 x 1024x64) 1.207;  weight macros (6 x 4096x80) 1.000;  param macros (2 x 4096x72) 1.002;  descriptor macro (256x32) 0.999;

Per-pass-type energy: not available (the SDF run covers the full image in one SAIF window).

## Summary (400 MHz, SDF SAIF, +dat)

308 mW = 123.3 uJ / inference (PT-only 198.6 mW, 79.4 uJ): internal / switching / leakage of the logic + macro
model; leakage 21.8 mW = 7.1 % (9.1 % at 3.3 ns).  0.222 pJ per dense-equivalent MAC (555.4 M + FC 5 120),
0.97 pJ per QC addition (127.3 M per image).  Top blocks: PE array 127.3 mW (41 %), activation macros 84.8 (27 %),
weight macros 39.1 (13 %), PPU 34.8 (11 %), param macros 10.0 (3 %), AGU + xbar + seq + host 7.0 (2 %); clock
network (cross-cutting) 60.9 mW.  Glitch factor SDF / zd 1.34 on the dynamic PT power (PE array 1.39, PPU 1.36).
