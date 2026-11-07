# ResNet-8 on the KUL GeMMX cluster: gate-level simulation and SAIF power (phase 3)

The heaviest ResNet-8 layer runs on the synthesised KUL cluster netlist inside the full chimera SoC (CVA6 host,
memory island and testbench in RTL, cluster = DC netlist), with the same ELF as the RTL run. The output is checked
against the PyTorch int8 reference, the cycle counts against RTL, and a SAIF of the layer window feeds PrimeTime PX.

## Netlist: `kul_w4.2p` (re-synthesis of the current RTL)

`kul_w4.2` predates the icache PMA fix (da1b522). `kul_w4.2p` is the same run (`impl/kulcluster/run.sh all 4.2
kul_w4.2p`: DC 2024.09, kit WLM `WireAreaLowkCon` enclosed, 4.2 ns at ss, same SDC) on the current pickle. The
pickle diff is one line (the cached-region base/mask) apart from Chisel's hashed module names. DC took 49 min.

| | `kul_w4.2` | `kul_w4.2p` | delta |
|---|---|---|---|
| total / logic area | 4.040 mm2 / 1509 kGE | 4.046 mm2 / 1513 kGE | +0.16 % / +0.3 % |
| GeMMX (GeMM + SIMD, streamer, CSR) | 1.010 mm2 | 1.014 mm2 | +0.3 % |
| fmax ss / tt / ff (PT, pre-CTS) | 229.3 / 353.7 / 503.1 MHz | 232.9 / 356.8 / 505.8 MHz | +1.6 / +0.9 / +0.5 % |

The deltas are synthesis noise. Details are in `impl/kulcluster/results/kul_w4.2p/`.

## Layer choice: conv1

conv1, conv2, conv4 and conv7 all have 4 608 array fires (2.36 M MACs). conv1 (3x3, 16 -> 16, 32x32) was chosen
for three reasons:
* it comes first, so the gate-level run has the least simulated time before it (0.7 ms vs 1.74 ms for conv7);
* it has the longest busy window (6 192 cycles);
* conv0 runs before it on the same netlist and is checked too.

conv7 utilises the array slightly better (76 % vs 74 % fires / busy).

## Gate-level simulation (`nn/gls/run_gls.sh`)

The ELF is built with `-DNN_STOP_AFTER=2`. Core 0 runs input DMA, conv0 and conv1, checksums every step against the
reference and then freezes. The run ends when `nn_result.marker` reads `0xdead0002`. The 32 TCDM macros are then
dumped and conv1's output is compared byte by byte with `IntResNet8` (`nn/gls/tcdm_macro.py` decodes the column-mux
layout of the ARM macro model, then `nn/sim/tcdm_check.py` does the compare). Each RTL reference is
`nn/sim/run_rtl.sh -c <clk>` with the identical ELF (same md5).

| run | conv1 output vs PyTorch int8 | step cycles (input / conv0 / conv1) | GeMMX / streamer busy (conv1) | vs RTL at the same clock | X / timing | wall |
|---|---|---|---|---|---|---|
| zero delay, 2 ns (TB default = RTL run) | **16384 / 16384 bytes exact**, checksums exact | 4938 / 7623 / 10329 | 6203 / 6204 | **identical**: cycles, counters, busy edges to the ps | 0 X on AXI / busy | 7.2 min |
| SDF tt, 2.8 ns (= tt fmax 356.8 MHz) | **exact** | 3587 / 7201 / 9980 | 6162 / 6163 | **identical** cycles and counters; edges +-40 ps (clock-to-Q) | 0 timing-check errors, 0 X | 14.4 min |
| SDF tt, 5.0 ns (200 MHz) | **exact** | 2502 / 6756 / 9649 | 6162 / 6163 | **identical**; edges +-40 ps | 0 timing-check errors, 0 X | 14.3 min |
| zero delay, 2 ns, through add1 (power proxy for core work) | conv0..add1 checksums exact, add1 **16384 bytes exact** | ... add1 165830 | | **identical** (3 GeMM windows to the ps) | 0 X | 10.4 min |

* The cycle counts depend on the cluster / SoC clock ratio. The SoC clock stays at 5 ns, so memory-island accesses
  cost fewer cluster cycles at a slower cluster clock. Each gate-level run therefore matches the RTL run at its own
  clock, and the 2 ns runs also match the phase-2 RTL timing.
* SDF: DC `write_sdf` at tt, in the ideal-clock view of `flow/tsmc65/sim/sdf_idealclk.py`: ICG and reset-tree
  IOPATHs are zeroed and the input ports get the 0.84 ns SDC input delay. The full ARM macro timing models and
  timing checks are on. The only warnings are vsim-3448 (negative timing-check limits clamped to 0) at time 0.
  The SDF run did not hang or diverge.
* Logs: `gls_logs/*_summary.txt`.

## Power (PrimeTime PX, tt 1.0 V 25 C, SAIF of the GeMM busy window, `nn/gls/power.sh`)

The SAIF covers the whole cluster netlist from the rising to the falling edge of BlockGemm `io_busy_o` for conv1:
6 192 cycles at zd 2 ns, 6 151 in the SDF runs. Questa `power report -all` includes nets that never toggle, so
**100 %** of the nets are annotated in zd and **98.9 %** with SDF. PT runs at the GLS clock and with the same netlist and
SDC, pre-CTS: ideal clock and wire-load caps.

| SAIF from | clock | total | dynamic / leakage | GeMMX (array+SIMD / streamer) | rest of cluster | RF macros | conv1 energy | pJ/MAC cluster (GeMMX) | TOPS/W cluster (GeMMX) |
|---|---|---|---|---|---|---|---|---|---|
| SDF tt | **356.8 MHz** (2.8 ns, tt fmax) | **332 mW** | 317 / 15.8 mW | 197 mW, 59 % (176 / 20) | 135 mW | 84 mW | **5.72 uJ** (GeMMX 3.39) | **2.43 (1.44)** | **0.82 (1.39)** |
| SDF tt | **200 MHz** (5 ns) | 194 mW | 178 / 15.8 mW | 113 mW, 58 % (101 / 12) | 81 mW | 50 mW | 5.96 uJ (3.48) | 2.53 (1.47) | 0.79 (1.36) |
| zero delay | 500 MHz (2 ns) | 383 mW | 367 / 15.8 mW | 204 mW, 53 % (179 / 25) | 179 mW | 114 mW | 4.74 uJ (2.53) | 2.01 (1.07) | 1.00 (1.87) |
| zd, add1 window (cores only) | 500 MHz | 86 mW | 71 / 15.8 mW | 16 mW (idle, ICG clock pins) | 71 mW | 14 mW | 141 pJ dynamic / cycle | | |

MACs = 4608 fires x 512 = 2.36 M useful MACs, 2 ops / MAC. The window also includes the ~26 % of busy cycles in which the
array does not fire (streamer stalls).
* Glitches: the zero-delay SAIF misses 25 % of the GeMMX energy (2.53 vs 3.39 uJ), which is glitching in the
  multiplier / adder trees. The SDF numbers are the reference.
* Dynamic energy per layer is the same at 2.8 and 5 ns (5.45 vs 5.47 uJ). Most of the 0.24 uJ difference in total
  energy is leakage over the longer window (0.21 uJ).
* In the conv window the clock network (ICG internal power, ideal clock) is 64 mW at 357 MHz, about 19 %.

### Energy per image (extrapolated, `nn/gls/energy.py --other add1_zd_2000ps`)

E_image = (conv1 energy / conv1 busy cycles) x 35 580 GeMMX busy cycles per image + (add1 energy per cycle) x the other
366 118 cycles. The cycle counts are from RTL at 2 ns (mean of 30 images).

| clock | convs | other (adds, pool+FC, DMA waits, CSR setup) | per image | latency | average power |
|---|---|---|---|---|---|
| 356.8 MHz (tt fmax) | 33 uJ | 68 uJ | **~101 uJ** | 1.13 ms | ~90 mW |
| 200 MHz | 35 uJ | 81 uJ | ~115 uJ | 2.0 ms | ~57 mW |

Over a whole image that is 25.0 M ops / 101 uJ = **0.25 TOPS/W**, because 91 % of the cycles are core work.

Caveats:
1. The "other" cycles use the activity of one residual add (zero delay: no glitches). Pool+FC, border fills and
   CSR programming are assumed to behave like an add.
2. All conv layers are assumed to cost the same per busy cycle as conv1.
3. Pre-CTS: there is no clock tree, the clock is ideal and the net capacitance comes from the wire-load model. A real
   clock tree typically adds 20-40 % to dynamic power.
4. The memory island, the host and the AXI outside the cluster are not included.
5. At clocks other than 2 ns the per-image cycle count differs by about 1 %, from the clock-ratio effect above.

## Paper sanity check (energy efficiency, normalised to 65 nm / 1.0 V)

The scaling rule is the one in `llmdocs/paper_reference.md` section 4: E ~ C V^2, with C x2.3-3 from 22 nm and x3-4 from 16 nm. The voltage
factor is (1.0 / V)^2.

| reference | published | normalisation | expected at 65 nm tt | ours | verdict |
|---|---|---|---|---|---|
| OpenGeMM [2], 16 nm SY, 0.675 V, 8x8x8 GeMM system incl. SPM, 32^3 matmul | 4.68 TOPS/W | / 6.6-8.8 | 0.53-0.71 TOPS/W | 0.82 cluster (1.39 GeMMX only) | **above**, x1.2-1.6 |
| SNAX cluster [3], 16 nm SY, 800 MHz, 227 mW, 0.924 TOPS/mm2 x 0.45 mm2 | ~1.8 TOPS/W | / 4.7-6.2 (V ~0.8 V assumed) | 0.30-0.39 TOPS/W | 0.82 | **above**, x2-3 |
| Voltra [4], 16 nm silicon, 0.6 V 300 MHz | 1.60 TOPS/W | / 8.3-11 | 0.14-0.19 TOPS/W | 0.82 | **well above**, x4-6 (flag) |
| Chimera TAC [1], 22 nm silicon, 0.6 V, 200 MHz (different accelerator) | 3.1 TOPS/W | / 6.4-8.4 | 0.37-0.48 TOPS/W | 0.82 | above, x1.7-2.2 |
| GeMMX array utilisation | 82-99 % [2], 92 % [3] | node-independent | | 74.4 % fires / busy (conv1) | lower: implicit-im2col streamer stalls (`rtl.md`) |

Our conv-layer efficiency is **higher than every scaled reference**, by about 1.2x (OpenGeMM, the closest config, post-synthesis like
ours) up to 6x (Voltra silicon). Expected reasons, in order:
1. Pre-CTS ideal clock (no clock tree), WLM and no IO. The silicon numbers of [4] and [1] also include the clock
   tree, power delivery, all memories at full activity and low-voltage leakage.
2. The CV^2 rule is crude across FinFET vs planar (16 nm FinFET pin capacitance is far lower than the factor-3-4
   length scaling suggests, so the factor understates the gap).
3. The window is the steady-state conv only: no L2 traffic, no CSR setup.

Taking caveats 1-2 together, a ~2x overestimate of efficiency would not be surprising. The OpenGeMM comparison, the like-for-like
one (post-synthesis 8x8x8 system), is within 1.6x. Whole-image efficiency (0.25 TOPS/W) is below every
reference, because the residual adds on the cores dominate (`rtl.md`).

## Reproduce

```bash
impl/kulcluster/run.sh all 4.2 kul_w4.2p                                  # on tau1 (impl/kulcluster/README.md)
export KUL_GLS_DIR=/tmp/$USER/qcnn_nngls KUL_GLS_SYN=<build>/syn/kul_w4.2p
hw/kulcluster/gls/gls.sh compile zd; hw/kulcluster/gls/gls.sh compile sdf; hw/kulcluster/gls/gls.sh sdf
nn/sim/run_rtl.sh -H tau5 -n 1 -t rtl_stop_conv1 -l 5000 [-c 2800] -- -DNN_STOP_AFTER=2      # RTL reference
NN_GLS_RTL=build/nn_rtl/rtl_stop_conv1 nn/gls/run_gls.sh -m zd -c 2000 -s conv1               # 7 min
NN_GLS_RTL=build/nn_rtl/rtl_stop_conv1_2800ps nn/gls/run_gls.sh -m sdf -c 2800 -s conv1       # 15 min
nn/gls/run_gls.sh -m zd -c 2000 -s add1 -w "900 1000"                                         # add-window SAIF
nn/gls/power.sh conv1_sdf_2800ps sdf; nn/gls/power.sh add1_zd_2000ps zd                       # PT PX, ~2 min each
python3 nn/gls/energy.py --other build/nn_gls/add1_zd_2000ps build/nn_gls/conv1_sdf_2800ps
```
The SAIF, the SDF, the netlist and the full PT reports stay on the server. Only the summaries in `gls_logs/`
(design hierarchy, power groups, annotation statistics) are tracked.

## Erratum (2026-11-07): PT wire-load

`nn/gls/pt_power.tcl` never selected a wire-load model, so PrimeTime PX used the library default (WireAreaForZero:
zero wire capacitance), whereas DC sized the netlist with the kit's WireAreaLowkCon (enclosed). The array ablation
(`qcacc/results/ablation.md`) showed this reads 14-18 % low. `pt_power.tcl` now applies the synthesis WLM
(`common/lib.tcl` `qc_wire_load`, as DC, PT timing and `qcacc/ablation`); `NN_PT_ZWLM=1` reproduces the numbers
above. Same SAIFs, no new simulation. Summaries: `gls_logs/*_wlm.txt`, `gls_logs/energy_wlm.txt`. Corrected table:

| SAIF from | clock | total | dynamic / leakage | GeMMX (array+SIMD / streamer) | rest of cluster | RF macros | conv1 energy | pJ/MAC cluster (GeMMX) | TOPS/W cluster (GeMMX) |
|---|---|---|---|---|---|---|---|---|---|
| SDF tt | **356.8 MHz** (2.8 ns) | **391 mW** (+17.6 %) | 375 / 15.8 mW | 237 mW, 61 % (213 / 24) | 154 mW | 84 mW | **6.73 uJ** (GeMMX 4.08) | **2.85 (1.73)** | **0.70 (1.16)** |
| SDF tt | 200 MHz (5 ns) | 226 mW (+16.9 %) | 211 / 15.8 mW | 135 mW, 60 % (122 / 14) | 91 mW | 50 mW | 6.96 uJ (4.15) | 2.95 (1.76) | 0.68 (1.14) |
| zero delay | 500 MHz (2 ns) | 448 mW (+17.1 %) | 433 / 15.8 mW | 247 mW, 55 % (218 / 29) | 201 mW | 115 mW | 5.55 uJ (3.06) | 2.35 (1.30) | 0.85 (1.54) |
| zd, add1 window (cores only) | 500 MHz | 91 mW | 75 / 15.8 mW | 16 mW | 75 mW | 14 mW | 151 pJ dynamic / cycle | | |

Energy per image (same extrapolation): **110.4 uJ** at 356.8 MHz (convs 38.9 + other 71.4; ~98 mW; 0.23 TOPS/W) and
124.4 uJ at 200 MHz (40.3 + 84.2; ~62 mW), was 100.9 / 115.0 uJ. Leakage is unchanged; the RF macros barely move
(the WLM adds net capacitance to logic). In the paper sanity check the conv1 cluster efficiency becomes 0.70 TOPS/W
(1.16 GeMMX only): inside the scaled OpenGeMM range (0.53-0.71), x1.0 instead of x1.2-1.6; the other verdicts shift
by the same factor 0.85.
