# QC-GeMMX: results

Source files: `results/rtl.md`, `results/impl.md`, `results/ablation.md`, `../nn/results/{rtl,gls_power}.md` (WLM
erratum applied), `../qc/RESULTS.md`. TSMC 65 nm (tcbn65gplus), DC 2024.09 + PrimeTime PX, **pre-CTS, ideal clock,
wire-load model, no P&R**. Every number below is a measurement unless it is labelled ESTIMATE or DERIVED.

## 1. What was built

QC-GeMMX is the KU Leuven SNAX GeMMX cluster (`hw/kulcluster`) with the GeMM core replaced so that it runs the `qc/`
model **s2**. In s2 each 2x2 weight block is `[[a, b], [b, a]]`, with a, b in {-1, 0, 1}. The cluster keeps the 8x8x8
shape, the A / C / D streamers, the Snitch cores and the TCDM. It is a drop-in for chimera, with the same top and
the same CSR map for registers 0..17 (`ARCH.md`).

| block | change |
|---|---|
| GeMM array | per row: 2-point butterfly (x, x0+x1, x0-x1), shared by 8 columns; per tile: 4-way select + 3 adders (dense: 8 multipliers 9x9 + 7 adders); per column: code decoder. Accumulator, add-C and control are unchanged |
| B weights | 64 b per 8x8 tile (16 blocks x 4 b) instead of 512 b; B reader 1 x 64 b on a narrow TCDM port (was 8 x 64 b) |
| RescaleSIMD | per-output-channel requant table (64 x {int32 mult, int8 shift}, 81 CSRs), so there is one call per conv |
| streamer patch | transposer only on 512-b readers; `GEMMX_START/BUSY/PERF` moved to CSR 1124..1126 |
| compiler / runtime | `qcacc/compile` (codec, sign-flipped rows stored as -M with negated bias and multiplier, `qc` / `gemmx` modes), `nn/sw` reused through hooks (`-DNN_QC_RQ`) |
| unchanged | residual adds and pool+FC on the Snitch cores, memory island, host, DMA, A / C / D layouts |

## 2. Headline: ResNet-8 on GeMMX (dense) vs s2 on unmodified GeMMX (control) vs s2 on QC-GeMMX

Power and energy are SDF tt 1.0 V, SAIF of the conv1 busy window, and PT with the synthesis WLM. Ops are counted
dense-equivalent: 2 x 12.5 M MAC per image, 2.36 M MAC for conv1.

| quantity | dense | control | **QC** | QC / dense |
|---|---:|---:|---:|---:|
| int8 accuracy, CIFAR-10 10k | 87.30 % | 80.41 % | 80.41 % | **-6.89 pts** |
| RTL logits bit-exact (full SoC) | 30 / 30 | 3 / 3 | 30 / 30 | |
| GLS conv1 output (zd + SDF tt) | exact | exact | exact | |
| GeMMX calls / image | 9 | 42 | 9 | |
| cycles / image (RTL) | 401 698 | 474 310 | 400 346 | 0.997 |
|   convs / residual adds / pool+FC / input DMA | 63 513 / 300 555 / 35 305 / 2 325 | convs 135 639, rest 338 671 | 62 046 / 300 593 / 35 349 / 2 358 | |
|   GeMMX busy (fires 25 856) | 35 580 (72.7 %) | 36 017 (71.8 %) | 31 692 (81.6 %) | 0.89 |
| latency at tt fmax (357 MHz) | 1.125 ms | 1.328 ms | 1.121 ms | 1.00 |
| cluster area (logic + 1.867 mm2 RF) | 4.046 mm2 | same netlist | 3.573 mm2 | 0.88 |
| logic | 1513 kGE | | 1184 kGE | 0.78 |
| GeMMX (array + SIMD + CSR + streamer) | 704 kGE | | 376 kGE | 0.53 |
| GeMM array | 439.6 kGE | | 114.7 kGE | 0.26 |
| fmax ss / tt / ff | 232.9 / 356.8 / 505.8 MHz | | 232.8 / 357.1 / 505.3 MHz | 1.00 |
| conv1 power at 357 MHz (GeMMX / array) | 390.8 mW (237.0 / 183.8) | 392.7 mW | 240.5 mW (127.1 / 79.8) | 0.62 |
| clock network share of conv1 power | 17.3 % | 17.4 % | 26.7 % | up |
| conv1 energy, pJ/MAC cluster / GeMMX / array | 6.73 uJ, 2.85 / 1.73 / 1.34 | 6.56 uJ, 2.78 / 1.65 / 1.30 | 3.67 uJ, 1.56 / 0.82 / 0.52 | 0.55 |
| conv1 at 200 MHz | 226.4 mW, 6.96 uJ | 227.4 mW, 6.78 uJ | 141.0 mW, 3.85 uJ | 0.55 |
| energy / image, 357 MHz (convs + other) | 110.4 uJ (38.9 + 71.4) | 124.7 uJ (39.6 + 85.1) | 89.2 uJ (21.3 + 67.9) | **0.81** |
| energy / image, 200 MHz | 124.4 uJ (40.3 + 84.2) | 141.3 uJ | 100.6 uJ (22.3 + 78.2) | 0.81 |
| TOPS/W, conv1 cluster / all convs / whole image | 0.70 / 0.68 / 0.227 | 0.72 / 0.67 / 0.201 | 1.29 / 1.24 / 0.280 | 1.84 / 1.82 / 1.23 |
| B weight tiles (bytes) | 77 440 | 77 440 | 9 680 | 0.125 |
| conv blobs in the ELF (B + bias + `nn_conv_t` [+ table]) | 91 072 | 101 632 | 26 880 | 0.30 |

Energy per image is extrapolated from conv1, as in `impl.md` section 4. The hardware weight code is 1 b / weight
(4 b per 2x2 block). That is lower than the 0.188 storage ratio in `qc/RESULTS.md`, which counts a generic
(valid, shift, sign) slot format.

**Where QC is not better.** Accuracy is 6.9 points lower. Latency and fmax are unchanged: the cores' residual adds
set the latency, and the critical paths are outside the array. Per-image energy improves only x0.81, while the convs
alone improve x0.55. The clock network's share of conv power rises to 27 %, so a real clock tree costs QC relatively
more. And in the array, the QC butterfly uses 10 % more energy than plain ternary (section 3). Control vs dense
shows that ternary weights in int8 multipliers save nothing (conv1 x0.97), and the 42 per-group calls make the
control 13 % worse per image.

## 3. Ablation: dense int8 vs plain ternary vs QC array (standalone cores, conv1, full rate, 4866 cycles)

| core | B / fire | area 4.2 ns (kGE) | per tile um2 | fmax ss at 2.0 ns | conv1 SDF+WLM | pJ / MAC | zd energy | SDF / zd |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| dense (dense ResNet-8 conv1) | 512 b | 432.6 | 9 233 | 340 MHz (MAC datapath) | 2.85 uJ | 1.207 | 2.05 uJ | 1.39 |
| dense (s2 as int8) | 512 b | 432.6 | 9 233 | | 2.80 uJ | 1.186 | 2.07 uJ | 1.35 |
| ternary (s2) | 128 b | 116.9 | 2 152 | 454 MHz (control path) | **1.00 uJ** | **0.425** | 0.76 uJ | 1.32 |
| QC (s2) | **64 b** | 114.1 | 1 962 | 465 MHz (control path) | 1.11 uJ | 0.468 | 0.77 uJ | 1.43 |

**Verdict.** Removing the multipliers gives the compute gain. Dense -> ternary accounts for 99 % of the area saving,
and gives array energy x0.35 against x0.39 for QC. The QC butterfly saves 2.4 % area (7 % at 2.0 ns). It costs **10 %
more array energy** with SDF delays (+2 % at zero delay), because the butterfly -> select -> adder chain glitches
more. What the QC structure buys over ternary is the weight stream and storage: **2x less than 2-bit ternary**
(16 vs 32 B per tile) and **8x less than int8**. In the cluster, RF-macro power during conv1 fell 35 % vs the
control. Part of that drop would also go to a ternary cluster; this was not measured.

**Implication (not built).** A "QC storage + ternary compute" variant would be the better design. It would keep the
64-b codes and B reader, decode each column's code to 8 trits (the decoder is already per column, 0.3 kGE), and feed
a plain ternary tile. That combines the ternary array energy with the QC weight traffic.

## 4. Amdahl: the cores dominate

Residual adds are 75 % of the cycles in both designs. The "other" energy (adds, pool+FC, CSR setup) is 65 % of the
dense image energy and 76 % of the QC image energy. It is priced at the measured add1-window energy per cycle:
195.1 pJ (dense) and 184.1 pJ (QC) at 357 MHz.

| ESTIMATE (not measured), 357 MHz | dense | QC | QC / dense |
|---|---:|---:|---:|
| measured: as built | 110.4 uJ | 89.2 uJ | 0.81 |
| adds cost 25 % of today's cycles | 66.4 uJ | 47.7 uJ | 0.72 |
| adds cost 10 % of today's cycles | 57.6 uJ | 39.4 uJ | 0.68 |
| adds removed (lower bound; 200 MHz: 55.4 / 36.7 uJ) | 51.7 uJ | 33.8 uJ | 0.65 |

Method: E = convs (measured extrapolation) + (other cycles - removed add cycles) x the measured "other" pJ/cycle.
The energy of running the adds elsewhere (for example on GeMMX as a 1x1 GEMM) is not included. Even with free adds,
QC's image gain stays at ~x0.65 because of pool+FC and the CSR / border work on the cores.

## 5. Sanity checks against the literature (normalised to 65 nm, 1.0 V)

Scaling rule (`README.md`, `llmdocs/paper_reference.md` section 4): E ~ C V^2. C goes x2.3-3 from 22 nm and x3-4
from 16 nm; the voltage factor is (1.0 / V)^2. Tags from the literature notes: [V] verified in the primary source,
[A] abstract only, [U] unverified.

| quantity | ours | published | node / V | normalised expectation | verdict |
|---|---|---|---|---|---|
| multiplier -> select tile area ratio | 4.7x (QC tile), 4.3x (ternary), cluster 4.6x | YodaNN: SoP area 5.3x smaller, 12b MAC -> binary [V] | UMC 65 nm | same node; < 5.3x expected, because our int32 accumulator is in every tile and our multiplier is 9x9 | **consistent** |
| int8 MAC energy (array) | 1.21 pJ (standalone), 1.34 (cluster, incl. stalls) | Horowitz 45 nm 0.9 V: 8b mult 0.2 + 32b add 0.1 pJ [V] | 45 nm | 0.6-1.0 pJ (x2-3, ESTIMATE from notes) | above x1.2-2: includes registers, clock, glitches; **plausible** |
| ternary select + acc energy | 0.43 pJ (ternary), 0.47 (QC) | Horowitz-derived ~0.1 pJ [V inputs, derived] | 45 nm | 0.2-0.3 pJ | above x1.4-2, same overheads; **plausible** |
| int8 / ternary array energy ratio | 2.8x (QC 2.6x) | ~3x arithmetic only (Horowitz-derived); YodaNN core 5.1x at 1.2 V [V] | | 3-5x | **at the low end**: the accumulator, clock and input cut are shared overheads |
| cluster conv TOPS/W (dense) | 0.70 (conv1) | OpenGeMM 4.68 [V]; SNAX ~1.8; Voltra 1.60 | 16 nm, 0.675 / ~0.8 / 0.6 V | 0.53-0.71 / 0.30-0.39 / 0.14-0.19 | in range of OpenGeMM; above SNAX / Voltra (no clock tree, no IO) |
| cluster conv TOPS/W (QC) | 1.29 (dense-equivalent ops) | no 65 nm ternary-weight int8 cluster found | | | gain x1.84 comes from the array + B traffic |
| array share of system power | 47 % (dense conv1: 183.8 / 390.8 mW) | OpenGeMM GeMM core 13.2 % of power, SPM 41.9 % [V] | 16 nm | node-independent share | **disagrees (flag)**: our array is relatively heavy (or our SRAM light: RF macros 21 %), so the multiplier removal gains more here than OpenGeMM's breakdown would allow (~1.15x) |
| energy / ResNet-8 image | dense 110.4, QC 89.2 uJ | GAP9 27.7 uJ (board, measured) [V]; SNAX+OpenGeMM 28 uJ (synthesis) [V]; DIANA 37 uJ digital [V of quote] | 22 nm 0.65 V; 16 nm (V n/s, 0.8 assumed); 22 nm (V n/s, 0.8 assumed) | 151-197; 132-175; 133-170 uJ | **below (flag)**: dense at x0.56-0.84 of the scaled values; cluster only (no memory island, host, IO), pre-CTS |
| structured weights, silicon at 65 nm | QC 1.29 TOPS/W (b = 2, int8 act, 1.0 V) | STICKER-T 3.76-14.4 TOPS/W average (block 8-128, FFT, 0.54-1.15 V) [A] | 65 nm | same node; block size 8-128 compresses 4-64x more | lower, as expected; context only |
| structured weights, synthesis | | PermDNN 614.4 GOPS / 703.4 mW = 0.87 TOPS/W [V]; CirCNN 10.0 "equivalent" TOPS/W, 16 b [V via PermDNN] | 28 nm; 45 nm | ~0.22-0.29; ~3.3-5 equiv. TOPS/W (x3-4 / x2-3, notes) | context only: different ops definitions, FC layers, large compression |

## 6. What was tried, what failed, and why

| item | outcome |
|---|---|
| one GeMMX call per 8-output-channel group (42 calls; the RescaleSIMD has 8 lane multipliers, s2 needs per-channel) | bit-exact, but each call costs ~2.2 k cycles outside the busy window (the model assumed 120): 475 715 cycles / image. Fixed in hardware with the requant table (9 calls, 400 346); the control keeps 42 calls (474 310) |
| upstream `PipelinedRescaleSIMD` | mis-handles output back-pressure (shifts the output register without a handshake, also with the table disabled). Found in the unit TB. Never triggered in the cluster (D8 writer does not stall); the TB stalls the input only. Not fixed |
| PT power with zero wire load | `nn/gls/pt_power.tcl` never set a WLM, so PT read 14-18 % low. The ablation exposed it; fixed (synthesis WLM, `NN_PT_ZWLM=1` restores the old view). Ratios moved little (image QC/dense x0.82 -> x0.81) |
| streamer transposer | upstream `require`s every reader to be 512 b when `has_transpose`; patched to put the transposer only on 512-b readers, and B moved to a narrow TCDM port |
| QC butterfly | glitches: SDF / zd energy 1.43 vs 1.32 for ternary, which turns a 2 % zero-delay gap into 10 % |
| CSR placement | the table registers must precede the CSR manager's start register, so `GEMMX_START/BUSY/PERF` moved to 1124..1126 and need literal `csrw` (snRuntime's switch stops at 1063) |

## 7. Limitations and assessment

* Pre-CTS, ideal clock, wire-load model, no IO; no P&R. The Cadence licence is refused for this user, and OpenROAD
  did not finish on the base KUL cluster (global route stopped; post-CTS ss WNS -3.67 ns). A clock tree typically
  adds 20-40 % dynamic power, and more for QC (27 % clock share).
* Gate-level power was measured for conv1 and an add1 window only. Other convs are extrapolated per busy cycle. conv0
  (padded Cin), conv5 and conv8 (1x1, low utilisation) were not simulated at gate level. The memory island and host
  are excluded.
* One trained seed per model; one image for the power windows; control RTL on 3 images.
* SIMD output-stall bug upstream (unfixed); the accumulator vs select-add split inside a tile is not measured.

**Assessment.** What is new: a complete, bit-exact path for a quasi-cyclic (b = 2, signed) ResNet-8, from training
to full-SoC RTL, gate-level simulation and SAIF power, in a public GeMMX cluster. It comes with a model-only control
and an array ablation that separate the effects of the model, the multipliers and the QC structure. The gains are
GeMMX area x0.53, conv energy x0.55, image energy x0.81, and weight storage x0.125 (2x below ternary).

What is weak:
* -6.9 points of accuracy on ResNet-8.
* The compute gain is the known multiplier -> ternary effect (YodaNN-class), and the QC compute structure itself is
  slightly worse than ternary.
* Image-level gains are capped by the core-side adds.
* No layout.

A publishable version would need:
* P&R with a clock tree (commercial tools);
* residual adds offloaded from the cores;
* the QC-storage + ternary-compute variant, and a 2-bit ternary cluster to measure the B-traffic share;
* a larger network (the width x2 probes in `qc/RESULTS.md` recover most of the loss) where the accuracy cost is smaller.

## 8. Reproduce

| experiment | command |
|---|---|
| model / codec tests | `python3 -m qcacc.model.test_model` |
| schedule model, 1000 images (+ 10k accuracy) | `python3 -m qcacc.compile.main --mode qc`; `--mode gemmx --acc` (control) |
| native C runtime | `qcacc/sw/native.sh qc\|gemmx [-DNN_FULL_CHECK]` |
| chimera ELF | `qcacc/sw/build.sh dense\|gemmx\|qc` |
| RTL generate / unit TBs | `qcacc/hw/gen.sh`; `qcacc/hw/tb/run.sh 30` |
| full-SoC RTL | `qcacc/hw/sim/run_rtl_qc.sh -H usask -n 10 [-f 10]`; control `-m gemmx -g` |
| synthesis + STA | `qcacc/impl/run.sh all 4.2 qc_w4.2` (tau1) |
| GLS | `qcacc/gls/run_gls_qc.sh -d qc -m sdf -c 2800`; `-d gemmx -m sdf -c 2800 -k 3` (and `-k 4`); add1: `-m zd -c 2000 -s add1 -w "900 1000"` |
| power / energy | `qcacc/gls/power_qc.sh -d qc\|gemmx <tag> sdf\|zd`; `python3 -m qcacc.gls.energy_qc [--clock 5000]` |
| ablation | `qcacc/ablation/run.sh [-H tau1]` (~40 min) |
| dense baseline | `nn/sim/run_rtl.sh`; `nn/gls/run_gls.sh`, `nn/gls/power.sh`, `nn/gls/energy.py` (`nn/results/gls_power.md`) |
