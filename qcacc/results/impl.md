# s2 on the QC-GeMMX cluster: TSMC 65 nm synthesis, gate-level simulation and SAIF power (M3)

Same flow, settings and methodology as the dense baseline (`impl/kulcluster/README.md`, `nn/results/gls_power.md`).
Three designs:
* **dense**: dense ResNet-8 on the base netlist `kul_w4.2p` (existing numbers; its SAIFs were re-run through PT with
  the block hook and give the same totals: 332.3 / 193.7 / 86.3 mW).
* **control**: s2 as int8 ternary weights on the **base** netlist `kul_w4.2p` (gemmx mode, 42 per-group calls). This
  separates the effect of the model (ternary weights in dense MACs) from the effect of the hardware.
* **QC**: s2 on the QC-GeMMX netlist `qc_w4.2` (QC array, 64-b B reader, requant table, 9 calls).

**Caveat for every number below: pre-CTS, ideal clock, wire-load model (no P&R parasitics), no IO.**
The baseline caveats in `nn/results/gls_power.md` apply unchanged: a real clock tree typically adds 20-40 % to the
dynamic power, and the clock network is a larger share of the QC design.

## 1. Synthesis (`qcacc/impl/run.sh all 4.2 qc_w4.2`, tau1)

The flow is identical to `kul_w4.2p`: `impl/kulcluster/run.sh` with `KUL_PICKLE` set to the QC pickle. That means DC
2024.09, kit WLM WireAreaLowkCon (enclosed), 4.2 ns at ss, the same SDC and the same 38 RF macros, then PT at ss / tt / ff.
`run.env` is identical except for the tree path. DC took 47 min.

| | `kul_w4.2p` (base) | `qc_w4.2` (QC) | delta |
|---|---|---|---|
| total area | 4.046 mm2 | **3.573 mm2** | -0.473 mm2 (-11.7 %) |
| logic area (kGE) | 2.179 mm2 (1513) | **1.705 mm2 (1184)** | -21.7 % |
| RF macros | 1.867 mm2 | 1.867 mm2 | 0 |
| GeMMX accelerator | 1.014 mm2 (704 kGE) | **0.542 mm2 (376 kGE)** | -46.5 % |
| cells / registers | 589 k / 96.7 k | 470 k / 94.7 k | -20 % / -2 % |
| fmax ss / tt / ff (PT) | 232.9 / 356.8 / 505.8 MHz | **232.8 / 357.1 / 505.3 MHz** | unchanged |
| PT vectorless power ss / tt / ff | 201 / 232 / 320 mW | 195 / 229 / 313 mW | |

fmax does not change because the critical paths are outside the array and are the same in both netlists. At ss
the limit is the SIMD rescale lane to the streamer writer; at tt / ff it is core 0's accelerator request to the xDMA
address generator.

GeMMX block split (`qcacc/impl/blocks.py`, um2 at ss; `impl_logs/{qc_w4.2/blocks.txt, kul_w4.2p_blocks.txt}`):

| block | base um2 (kGE) | QC um2 (kGE) | QC / base |
|---|---:|---:|---:|
| GeMM array, total | 633 030 (439.6) | **165 110 (114.7)** | **0.26** |
|   64 tiles | 601 091 (417.4), 9 392 / tile | 130 596 (90.7), 2 041 / tile | 0.22 |
|   8 row butterflies | - | 11 786 (8.2) | |
|   column decoder | - | 397 (0.3) | |
|   rest (input cut, control) | 31 940 (22.2) | 22 332 (15.5) | 0.70 |
| SIMD rescale (+ requant table logic) | 177 360 (123.2) | 182 606 (126.8), table 4 637 | 1.03 |
| CSR manager (QC: + 81 table registers) | 7 061 (4.9) | 33 284 (23.1) | 4.7 |
| streamer | 195 354 (135.7) | 160 168 (111.2) | 0.82 (1 x 64-b B reader) |
| glue | 943 | 902 | |
| **GeMMX** | **1 013 749 (704.0)** | **542 071 (376.4)** | **0.53** |
| rest of cluster: logic / RF macros | 1 165 028 / 1 867 293 | 1 163 340 / 1 867 293 | 1.00 |

The requant table costs 31 k um2 in total (CSR registers plus select logic, 1.9 % of the QC logic). The array is 3.8x
smaller, and each tile is 4.6x smaller, because the int8 multipliers are replaced by a 4-way select-add.

## 2. Gate-level simulation (`qcacc/gls/run_gls_qc.sh`, tau1, Questa 2022.1)

This is `nn/gls/run_gls.sh` through env hooks. The full chimera SoC runs with the cluster as a DC netlist, using the
same ELF as the RTL reference (md5 identical). The RTL references are `qcacc/hw/sim/run_rtl_qc.sh -c <clk> --
-DNN_STOP_AFTER=<idx>`. The output is checked byte by byte in the TCDM dump (`qcacc/gls/tcdm_check.py`, s2
`IntResNet8`). SDF: DC tt `write_sdf` in the ideal-clock view, macro timing models, timing checks on. QC tt fmax is
357.1 MHz (> 356.8), so the SDF clock is **2.8 ns as in the baseline**.

| run | conv1 (add1) output vs s2 int8 ref | step cycles (input / conv0 / conv1) | GeMMX / streamer busy conv1 | vs RTL, same clock | X / timing | wall |
|---|---|---|---|---|---|---|
| QC zd 2 ns | **16384 / 16384 exact**, checksums exact | 4858 / 7656 / 9746 | 5473 / 5477 | **identical**, busy edges to the ps | 0 X | 6.3 min |
| QC SDF tt 2.8 ns | **exact** | 3530 / 7176 / 9416 | 5461 / 5465 | **identical** cycles and counters; edges +-40 ps | 0 errors, 0 X | 9.4 min |
| QC SDF tt 5 ns | **exact** | 2368 / 6666 / 9097 | 5476 / 5480 | **identical** | 0 errors, 0 X | 9.4 min |
| QC zd 2 ns through add1 (SAIF 900-1000 us) | add1 **16384 exact** | ... add1 163572 | | **identical** (3 GeMM windows) | 0 X | 2.7 min |
| control SDF tt 2.8 ns (2 runs, SAIF of call 3 / call 4) | conv1 (both groups) **exact** | 3602 / 5050+4538 / 6097+5918 | 2983+3002 | **identical**; edges +-40 ps | 0 errors, 0 X | 16 / 12 min |
| control SDF tt 5 ns (2 runs) | **exact** | 2507 / 4603+4250 / 5765+5632 | 2983+3002 | **identical** | 0 errors, 0 X | 15 / 14 min |
| control zd 2 ns through add1 (SAIF 980-1080 us) | add1 **exact** | ... add1 163583 | | **identical** (6 GeMM windows) | 0 X | 2.9 min |

The SAIF of the control covers both conv1 group calls. It takes one GLS run per call, because Questa's `power reset`
does not restart the SAIF (the second window would include the first window and the gap between them). The add1
windows sit at the same offset into add1 as the baseline's 900-1000 us. SDF annotation: 98.9 % of nets.

## 3. conv1 power (PrimeTime PX, tt, SAIF of the GeMM busy window, `qcacc/gls/power_qc.sh`)

The block split comes from `qcacc/gls/pt_blocks.tcl` (hierarchical-cell power). MACs are dense-equivalent: 4608 fires x
512 = 2.36 M. The conv1 MACs are the same in all three designs. Net capacitance: the synthesis WLM (WireAreaLowkCon,
enclosed), as DC and `qcacc/ablation` (since 2026-11-07; before, PT ran with zero wire cap: 2.8 ns conv1 332.3 / 335.1 /
210.1 mW, 5.72 / 5.60 / 3.21 uJ; per image 100.9 / 114.6 / 83.0 uJ, QC x0.82 of dense; `impl_logs/*_zwlm.txt`, `NN_PT_ZWLM=1`).

| SDF tt, 2.8 ns (357 MHz) | dense | control | **QC** |
|---|---:|---:|---:|
| window (busy cycles) | 6151 | 5963 (2972 + 2991) | **5450** |
| total power | 390.8 mW | 392.7 mW | **240.5 mW** |
| dynamic / leakage | 375.0 / 15.8 | 376.8 / 15.8 | 227.7 / 12.7 |
| GeMMX | 237.0 | 233.5 | **127.1** |
|   GeMM array (tiles / butterflies / decoder) | 183.8 (165.7 / - / -) | 184.2 (166.5) | **79.8 (69.9 / 2.6 / 0.2)** |
|   SIMD rescale (+ table) | 29.3 | 26.0 | 31.0 (table 0.05) |
|   CSR manager (+ table regs) | 0.26 | 0.26 | 0.61 |
|   streamer | 23.6 | 23.0 | 15.6 |
| RF macros | 84.1 | 87.4 | 57.1 |
| rest of cluster logic | 69.7 | 71.8 | 56.3 |
| clock network (ICGs, ideal clock) | 67.6 (17.3 %) | 68.2 (17.4 %) | 64.2 (**26.7 %**) |
| **conv1 energy** (GeMMX / array) | 6.73 uJ (4.08 / 3.16) | 6.56 uJ (3.90 / 3.08) | **3.67 uJ (1.94 / 1.22)** |
| pJ / MAC cluster / GeMMX / array | 2.85 / 1.73 / 1.34 | 2.78 / 1.65 / 1.30 | **1.56 / 0.82 / 0.52** |
| TOPS/W cluster / GeMMX | 0.70 / 1.16 | 0.72 / 1.21 | **1.29 / 2.43** |

The same comparison at 200 MHz (SDF tt, 5 ns):

| | dense | control | QC |
|---|---:|---:|---:|
| conv1 power, energy | 226.4 mW, 6.96 uJ | 227.4 mW, 6.78 uJ | **141.0 mW, 3.85 uJ** |
| pJ / MAC cluster / GeMMX | 2.95 / 1.76 | 2.87 / 1.69 | **1.63 / 0.84** |

* **Effect of the model** (control vs dense, same hardware): conv1 energy x0.97, array x0.97. Ternary weights in
  the dense int8 multipliers save almost nothing. A, the accumulators and the clock still toggle.
* **Effect of the hardware** (QC vs control, same model): conv1 energy x0.56, GeMMX x0.50, array x0.40. Busy cycles
  drop by 8.6 %, RF macro power by 35 % (8x less B traffic, fewer streamer stalls), and leakage by 20 %.
* The 64 tiles (4-term select-add plus int32 accumulator) are 88 % of the QC array's power. The clock
  network barely changes (64.2 vs 67.6 mW), because the register count is almost unchanged.
* Zero delay (2 ns) misses glitch energy, as in the baseline: QC conv1 3.00 uJ (GeMMX 1.43) vs 3.67 (1.94) with SDF.
  The SDF numbers are the reference.

## 4. Energy per image (`python3 -m qcacc.gls.energy_qc [--clock 5000]`, method of `nn/gls/energy.py`)

E_image = conv1 energy per busy cycle x the GeMMX busy cycles of each layer (RTL, 2 ns), plus the energy per cycle
of the add1 window (zero delay, same netlist and software) x the other cycles. Images: dense 401 698 cycles (busy
35 580); control 474 310 (36 017); QC 400 346 (31 692).

| conv energy per layer (uJ), 357 MHz | conv0 | conv1 | conv2 | conv3 | conv5 | conv4 | conv6 | conv8 | conv7 | all convs |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| dense | 3.34 | 6.74 | 6.76 | 3.54 | 1.13 | 6.83 | 3.37 | 0.58 | 6.64 | 38.9 |
| control | 3.55 | 6.58 | 6.62 | 3.57 | 1.18 | 6.83 | 3.61 | 0.70 | 6.96 | 39.6 |
| **QC** | 1.82 | 3.69 | 3.66 | 1.84 | 0.70 | 3.71 | 1.81 | 0.35 | 3.77 | **21.3** |

| per image | clock | convs | other (adds, pool+FC, CSR setup) | **total** | latency | avg power | convs pJ/MAC, TOPS/W | image TOPS/W (25.0 M ops) |
|---|---|---:|---:|---:|---:|---:|---|---:|
| dense | 357 MHz | 38.9 uJ | 71.4 | **110.4 uJ** | 1.125 ms | 98.1 mW | 2.94, 0.68 | 0.227 |
| control | 357 MHz | 39.6 | 85.1 | **124.7 uJ** | 1.328 ms | 93.9 mW | 2.99, 0.67 | 0.201 |
| **QC** | 357 MHz | **21.3** | 67.9 | **89.2 uJ** | 1.121 ms | 79.6 mW | **1.61, 1.24** | **0.280** |
| dense | 200 MHz | 40.3 | 84.2 | 124.4 uJ | 2.008 ms | 62.0 mW | 3.04, 0.66 | 0.201 |
| control | 200 MHz | 41.0 | 100.3 | 141.3 uJ | 2.372 ms | 59.6 mW | 3.09, 0.65 | 0.177 |
| **QC** | 200 MHz | 22.3 | 78.2 | **100.6 uJ** | 2.002 ms | 50.3 mW | 1.69, 1.19 | 0.249 |

QC vs dense per image: **x0.81** (-19.2 %; convs x0.55; the same x0.81 at 200 MHz). QC vs control: x0.72. The control is 13 % worse than dense
because of the 42 calls (+72.6 k cycles of CSR setup). Per image, the core-side residual adds dominate (76 % of the
QC energy is "other"). The QC "other" energy per cycle (184.1 pJ at 2.8 ns) is 6 % below dense (195.1), from leakage
and idle GeMMX clocking.

Extrapolation caveats (as in the baseline): every conv is assumed to cost what conv1 costs per busy cycle; pool+FC
and CSR setup are assumed to behave like add1; the memory island and host are not included; ideal clock, WLM, no
P&R.

## Reproduce
```bash
qcacc/impl/run.sh all 4.2 qc_w4.2          # tau1, tree /tmp/$USER/qcacc_syn/tree (rsync flow/tsmc65 hw/tech impl/kulcluster qcacc/impl + QC pickle)
KUL_BUILD=$PWD/build/qcacc KUL_GLS_DIR=/tmp/ckp908/qcacc_gls KUL_GLS_SYN=/tmp/ckp908/qcacc_syn/build/syn/qc_w4.2 \
  KUL_GLS_FLOW=/tmp/ckp908/qcacc_syn/tree/flow/tsmc65 hw/kulcluster/gls/gls.sh compile zd|sdf; ... gls.sh sdf (twice)
qcacc/hw/sim/run_rtl_qc.sh [-m gemmx] -H tau5 -t <d>_stop_conv1_2800ps -c 2800 -- -DNN_STOP_AFTER=<2|4>   # RTL refs
qcacc/gls/run_gls_qc.sh -d qc -m sdf -c 2800                     # + -m zd -c 2000; -s add1 -w "900 1000"
qcacc/gls/run_gls_qc.sh -d gemmx -m sdf -c 2800 -k 3             # and -k 4; -s add1 -w "980 1080" (zd)
qcacc/gls/power_qc.sh -d qc|gemmx <tag> sdf|zd                   # PT PX (WLM) + block hook; NN_PT_ZWLM=1: zero wire
python3 -m qcacc.gls.energy_qc [--clock 5000 --dense-run build/nn_gls/conv1_sdf_5000ps]
```
The control's GLS library is a copy of the base one (`/tmp/ckp908/qcacc_ctlgls`; the base build dirs are untouched).
The dense SAIFs were copied there and re-run through PT with the block hook.
Logs: `impl_logs/` (synthesis summaries and block splits, GLS summaries, PT power summaries, energy tables, RTL references).

## Open issues
1. No CTS / P&R: the ideal clock and WLM caveats above. The QC design's 27 % clock-network share means a real clock
   tree costs it relatively more than the dense design.
2. Per-layer energy is extrapolated from conv1. conv5 / conv8 (1x1, low utilisation) and conv0 (padded Cin) were
   not simulated at gate level.
3. 87 % of the QC array's power is in the tiles (select-add + int32 accumulator), and the clock network is 27 % of
   the cluster. The split between accumulator and select-add inside a tile was not measured (the hook stops at tile level).
