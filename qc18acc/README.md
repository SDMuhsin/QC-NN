# qc18acc/ — QC18-ACC: accelerator for the qc18 QC ResNet-18 (b = 8, signed)

Spec: [ARCH.md](ARCH.md) (incl. "Appendix: memory images and descriptors"). Reference network: `qc18/int8.py`
(`IntNet`, integer-exact), model `s8kd` (`/tmp/root/qc18/final/s8kd_s0/best.pt`, see `qc18/fetch.sh`).

**Versions.** v1 = git tag `qc18acc-v1` (results: `results/power.md`, netlist tag `qa_w3.3`).  **v2** (this tree;
results `results/power_v2.md`, netlist tag `qa2_w3.3`): (1) every SRAM macro CLK is gated by a tcbn65gplus
integrated clock gate (CKLNQD) enabled by the access request (`hw/tech/qa_sram_tech.sv`; behavioural `qa_sram`
unchanged); (2) per-tile tap order kh, cb, kw with an 8-word kw sliding window in the S3 registers (ARCH.md
"kw window"): a kw step shifts the window and reads only the new word, x0.433 array act-bank reads; (3) the PE is
split into function sub-instances (rotators, trit + 2-term add, accumulate add) for the power breakdown.
**v3** (Kb = 2, two QC blocks per PE per cycle; section "v3" below, results [results/v3.md](results/v3.md), netlist
tag `qa3_w3.3`): separate small trees `compile3/`, `hw3/`, `impl/v3/`, selected by `QA_V=3` in the shared impl / GLS /
power scripts; v2 stays the default build.  Numbers below this line are v1 unless marked v2 / v3.

## Compiler + golden model (`compile/`)

| file | contents |
|---|---|
| `codes.py` | 8x8 block coefficients <-> canonical 10-b codes; 80-b weight words, FC words, 72-b param words (field pack / unpack) |
| `layout.py` | raster / phase map index, bank / address, AGU rule (tile o0..o0+7, input index o_i + c(kh, kw, cb), padding lanes), tensor <-> buffer words, int16 R planes |
| `program.py` | pass schedule from `IntNet`, buffer rotation / layouts / bases + liveness and capacity check, weight / param / descriptor images, per-layer proofs (20-b acc, int32 v, \|R\| < 2^15), descriptor encode / decode |
| `golden.py` | bit-exact numpy model executing only the memory images (vectorised per pass; literal block-PE path for cross-checks), cycle-count MODEL |
| `ref.py` | `IntNet` built as `qc18.int8.main` does (calibration on train[:2000]) and its per-pass integer maps |
| `export.py` | `$readmemh` images: act buffers, weight / param / descriptor RAMs, per-image input, logits, per-pass output buffers |
| `main.py` | CLI: build, proofs, memory sizes, cycle model, bit-exact check vs `IntNet`, test accuracy, export |
| `test_compile.py` | unit tests (codes exhaustive, wide words, descriptors, AGU / banks for every pass / tile / tap, padding, block-PE, requant, int16 planes) |

```bash
python3 -m qc18acc.compile.test_compile
CUDA_VISIBLE_DEVICES=0 python3 -m qc18acc.compile.main --ckpt /tmp/root/qc18/final/s8kd_s0/best.pt --n 1000
CUDA_VISIBLE_DEVICES=0 python3 -m qc18acc.compile.main --n 0 --literal 0 --acc
CUDA_VISIBLE_DEVICES=0 python3 -m qc18acc.compile.main --n 0 --literal 0 --export /tmp/root/qc18acc/export --images 0,1,2,3
```

## RTL (`hw/`)

Synthesizable SystemVerilog of ARCH.md (+ Appendix formats), single clock, synchronous active-low reset, no
latches / initial blocks / vendor cells.  Every memory is a `qa_sram` (single port, registered read data).
File list for `flow/tsmc65` (syn + sim): `hw/rtl/qc18acc.f`, top `qa_top`.

| file | contents |
|---|---|
| `rtl/qa_pkg.sv` | sizes, modes, host address map, CSR addresses |
| `rtl/qa_sram.sv` | generic single-port SRAM wrapper `qa_sram #(WORDS, BITS)` (to be swapped for macros) |
| `rtl/qa_bankmem.sv` | wide single-port memory from N `qa_sram` banks: weights 6 x 4096 x 80 b, params 2 x 4096 x 72 b |
| `rtl/qa_actmem.sv` | act buffers A / B / C, 3 x 8 x (1024 x 64 b); array / PPU-write / residual / host requesters, bank-conflict assertions |
| `rtl/qa_host.sv` | 32-b host port (CSR, desc, param, weight, act regions; WSTAGE / RSTAGE for wide words), perf / logit CSRs |
| `rtl/qa_seq.sv` | descriptor fetch + decode, pass / head control, perf counters (total, per pass, array busy, stall, param load) |
| `rtl/qa_agu.sv` | step generator (og, tile, kh, cb, kw; v2), tap offset, kw-window state (shift, held slots, bank reads), per-bank addresses, padding mask, weight address, shadow-capture stall |
| `rtl/qa_xbar.sv` | S2 -> S3: kw window (8 raw words, shift + bank load), lane mask at the array input, code register |
| `rtl/qa_pe.sv`, `rtl/qa_array.sv` | QC block PE (2 rotators, trits, 8 x 20-b acc, shadow; v2 sub-instances `qa_pe_rot` / `qa_pe_tadd` / `qa_pe_acc`), 8 x 8 array with column shadow chains |
| `rtl/qa_drain.sv` | drain controller (64 / 128 cycles per tile), 64-entry param RF + loader, output / residual addresses, `cap_ok` |
| `rtl/qa_ppu_lane.sv`, `rtl/qa_ppu.sv` | 8-lane PPU, 6 register stages (32 x 31 multiply in 2), RELU / RAW16 / RES_ID / RES_R, head mode |
| `rtl/qa_head.sv` | pool (8 banks per cycle, via the PPU) + FC (1 weight word per cycle), overlapped per channel group |
| `rtl/qa_top.sv` | top level and memory port muxing |
| `tb/qa_tb.sv`, `tb/tb.f` | full-network TB: all loads through the host port, per image START..DONE, logits via CSRs, every stored map checked at each pass end (backdoor copy of the output buffer) |
| `tb/tb_pe.sv`, `tb/tb_ppu.sv`, `tb/ppu_vectors.py` | unit TBs: PE vs behavioural model, PPU lane vs golden arithmetic vectors |
| `tb/mini.py` | random mini program (compiler planner, H = 8, all 4 modes + head) for fast regressions |
| `sim/run_rtl.sh` | export -> rsync -> VCS on a tau host (`flow/tsmc65/sim/run_vcs.sh`) -> log summary + cycle table |
| `sim/run_unit.sh`, `sim/cycles.py` | local iverilog unit tests; measured-vs-model cycles per pass |

Pipeline (documented in the module headers): S0 AGU -> S1 address registers -> macro read -> S2 data -> S3 row /
code registers -> PE accumulate (capture 3 cycles after issue); drain D0 -> PPU r1..r6 -> buffer write.
Assumptions checked in simulation: power-of-two map sizes, H_out W_out >= 8, no two requests per bank per cycle.

```bash
qc18acc/hw/sim/run_unit.sh [mini]                 # local iverilog: tb_pe, tb_ppu (+ mini program full TB)
qc18acc/hw/sim/run_rtl.sh usask 0 4               # VCS RTL, s8kd, images 0..3 (QC_MINI=1: mini program)
```

v2 result (VCS S-2021.09, images 0..3, plain RTL and `QC_TECH=1` with macro models + clock gates): RESULT PASS,
all logits and all 20 stored maps bit-exact, 159 982 cycles / image (= v1), array act-bank reads (`CSR_ACT_RD`)
409 572 / image = the window model (v1: 946 644).  `python3 -m qc18acc.compile.main --n 200`: BIT-EXACT PASS (the
literal path goes through the window model `golden.gather_window`).

v1 result (VCS S-2021.09, images 0..3): RESULT PASS, all 10 int32 logits and all 20 stored maps bit-exact per image.
159 982 cycles / image START..DONE (model 162 640, -1.6 %); array busy 85.2 %, AGU stall 20 690, param load 4 800.
Passes > 5 % off the model: blocks.6.c1 -8.3 % (K = 288 > drain + param load, so the 64-cycle param load per og is
hidden behind the next tile; same effect -4.4 % in blocks.7) and the head -48 % (868 vs the 1680 estimate: 8 pixel
words per cycle and pool of group cb + 1 overlapped with the FC of group cb).

## Implementation, TSMC 65 nm (`hw/tech/`, `impl/`, `gls/`)

Flow and settings of `impl/kulcluster` (`flow/tsmc65`): DC W-2024.09 in wire-load mode with the kit WLM
WireAreaLowkCon (enclosed), tcbn65gplus 200a CCS, ss = wc 0.9 V 125 C / tt / ff = lt; PrimeTime pre-CTS, ideal
clocks, 0.25 ns setup uncertainty; IO delay 20 % of the period on the host port; `rst_n` (synchronous) not timed.
Builds and kit-derived views stay on the build host (`/tmp/$USER/qc18acc/build`, macros in `QC_MC_OUT` of
`flow/tsmc65/site/sram.sh`); the repo keeps numbers only (`impl/results/<tag>/{area,timing}.txt`).

| file | contents |
|---|---|
| `impl/macros.txt` | the 4 ARM macros (`mc_gen.sh gen`), choice in `sweep_result.txt` |
| `hw/tech/qa_sram_tech.sv` | `qa_sram` on the macros: 1024x64 -> `qa_act_1024x64m8`, 4096x80 -> `qa_wgt_4096x80m8`, 4096x72 -> `qa_par_4096x72m8`, 256x32 -> `qa_dsc_256x32m2` (flip-flops otherwise); hold register for the write-through macros (rdata = last read data, held over writes, like `qa_sram`) |
| `hw/tech/qc18acc_tech.f`, `hw/tech/macros_sim.f` | RTL file list with the tech `qa_sram`; macro Verilog models (`${QC_MC_OUT}`) |
| `impl/run.sh`, `constraints.sdc`, `dc_hook.tcl`, `pt_hook.tcl`, `summarize.py` | DC / PT (`macros`, `elab`, `syn`, `pt`, `summary`, `all <period>`), area per block / per PE, per-corner WNS / fmax / paths |
| `gls/run_gls.sh`, `gls/gen_snap.py`, `gls/gls.f` | zero-delay GLS of the full network on a netlist (VCS, cell + macro models), TB backdoor names from the netlist, SAIF over START..DONE of the first image; `QA_SDF=1`: tt-SDF timing-annotated run |
| `gls/write_sdf.tcl` | DC tt SDF of the netlist (synthesis WLM), made STA-consistent by `flow/tsmc65/sim/sdf_idealclk.py` (`run_gls.sh sdf`) |
| `power/power.sh`, `power/pt_power.tcl` | PrimeTime PX (tt, synthesis WLM, ideal clock) on a GLS SAIF: power groups, blocks, macro activity -> `results/power/` |
| `power/saif_scale.py`, `power/macro_dat.py`, `power/energy.py` | SAIF rescale to another clock (same toggles / cycle); macro access energy from the ARM datatables (the .lib CLK energies are 0); energy tables |

```bash
# on the build host, in the host-local clone /tmp/$USER/qc18acc/repo (git pull):
qc18acc/impl/run.sh macros                      # ~5 min, views in QC_MC_OUT (host-local)
qc18acc/impl/run.sh all 3.3                     # DC (~12 min) + PT ss/tt/ff + summary -> build/syn/qa_w3.3/res/
# locally:
QC_TECH=1 qc18acc/hw/sim/run_rtl.sh usask 0 2   # RTL with the macro models (mapping check)
qc18acc/gls/run_gls.sh start usask qa_w3.3 0 2  # GLS zero delay in the background on the host (~15 min / image)
qc18acc/gls/run_gls.sh check usask qa_w3.3      # status / result + cycle comparison with the RTL log
```

Tech mapping check (`QC_TECH=1`, VCS, ARM full models, zero delay): images 0..1 RESULT PASS, all logits and all
20 stored maps bit-exact (maps read back from the macro model arrays), 159 982 cycles / image as RTL.

Period sweep (DC target = ss period; fmax = 1 / (period - WNS); tt / ff on the ss netlist):

| tag | period | total mm2 | logic mm2 (kGE) | ss WNS / fmax | tt WNS / fmax | ff WNS / fmax |
|---|---|---|---|---|---|---|
| `qa_w3.0` | 3.0 ns | 6.386 | 0.839 (582) | -0.242 / 308.5 MHz | +0.866 / 468.7 | +1.536 / 682.9 |
| `qa_w3.2` | 3.2 ns | 6.444 | 0.897 (623) | -0.037 / 309.0 MHz | +1.077 / 470.9 | +1.727 / 678.9 |
| **`qa_w3.3`** | 3.3 ns | 6.433 | 0.885 (615) | **+0.002 / 303.2 MHz (met)** | +1.140 / 462.9 | +1.799 / 666.2 |
| `qa_w3.5` | 3.5 ns | 6.366 | 0.818 (568) | +0.003 / 285.9 MHz (met) | +1.224 / 439.4 | +1.899 / 624.6 |
| `qa_w4.0` | 4.0 ns | 6.353 | 0.805 (559) | +0.005 / 250.3 MHz (met) | +1.430 / 389.2 | +2.208 / 558.1 |

Chosen: **`qa_w3.3`** (shortest period that closes at ss; the 2.5 ns tt target of the RTL is met at tt with
+1.14 ns).  Critical path (ss and tt): weight-SRAM macro clock -> Q (1.23 ns at ss) -> hold mux -> 6-bank read mux
(`u_wmem`) -> head FC dot product (`u_head`, carry-save adder tree) -> `u_head/dot2_reg`, i.e. the FC stage of the
head, which reads a weight word and reduces it in the same cycle.  Into the macros (address from `u_seq` pass fields
through the AGU / bank select) slack +0.008 ns at ss.  ff: `u_head` logit accumulate / `u_seq` perf counters.
Hold: -0.13 ns (ss) on macro D pins from the host write-staging registers (pre-CTS; fixed in P&R).

Area of `qa_w3.3` (NAND2 = ND2D1 = 1.44 um2, from the library via the DC summary): total 6.433 mm2, macros 5.548 mm2
(86.2 %: 24 x 1024x64 2.756, 6 x 4096x80 2.124, 2 x 4096x72 0.647, 256x32 0.021), logic 0.885 mm2 = 615 kGE:

| block | logic kGE | % logic |
|---|---|---|
| PE array (64 x `qa_pe`, 6.26 kGE / PE) | 401.5 | 65.3 |
| PPU (8 lanes) | 105.8 | 17.2 |
| drain (param RF, loader) | 31.4 | 5.1 |
| act buffers (24 hold registers, port muxes) | 22.7 | 3.7 |
| head (pool + FC) | 19.7 | 3.2 |
| xbar | 8.0 | 1.3 |
| seq | 7.9 | 1.3 |
| weight / param / desc SRAM wrappers (hold, bank mux) | 7.3 | 1.2 |
| host port + CSRs | 4.0 | 0.6 |
| AGU | 3.8 | 0.6 |
| top glue | 2.7 | 0.4 |

Gate-level, zero delay (`gls/run_gls.sh`, `qa_w3.3` netlist, VCS, tcbn65gplus cell models + ARM macro models,
`+nospecify +notimingcheck`): images 0..1 RESULT PASS, all logits and all 20 stored maps bit-exact (maps read from
the macro model arrays through the netlist instance names), every per-pass cycle counter and the 159 982 cycles /
image START..DONE equal to RTL (44 counters compared); ~23 min CPU for load + 2 images.  SAIF of the whole DUT
(`qa_tb/dut`, netlist nets) over START..DONE of image 0 (cycles 84 255..244 240, 159 985
cycles at the TB clock 2.5 ns): `usask:/tmp/ckp908/qc18acc/gls/qa_w3.3/qa_top_img0.saif` (41 MB, host-local; for PT
power: `read_saif -strip_path qa_tb/dut`, rescale to the analysed clock).  The `qa_w3.5` netlist passed the same run
(image 0) on tau5.

Timing-annotated GLS and power ([results/power.md](results/power.md)):

```bash
qc18acc/gls/run_gls.sh sdf usask qa_w3.3                   # DC tt SDF + ideal-clock view (~1 min; call until listed)
QA_SDF=1 qc18acc/gls/run_gls.sh start usask qa_w3.3 0 1     # tt SDF, timing checks on, 2.5 ns (~1 h for load + 1 image)
QA_SDF=1 qc18acc/gls/run_gls.sh check usask qa_w3.3
qc18acc/power/power.sh [-p 3.3] qa_w3.3 sdf|zd             # PrimeTime PX on the SAIF (~1 min) -> results/power/
python3 qc18acc/power/energy.py                             # tables of results/power.md
```

SDF run (tt, 400 MHz, full image 0): RESULT PASS, all logits and maps bit-exact, 159 982 cycles and every pass
counter equal to RTL, 0 timing-check violations.  Power at 400 MHz (SDF SAIF, macros from the datatable model since
the macro .lib CLK energies are 0): **308 mW, 123 uJ / inference, 0.22 pJ / dense-equivalent MAC**, leakage 7.1 %;
PE array 41 %, activation macros 27 %, weight macros 13 %, PPU 11 %; glitch factor SDF / zd 1.34.

**v2** ([results/power_v2.md](results/power_v2.md)): netlist `qa2_w3.3` (`impl/run.sh all 3.3 qa2_w3.3`), 6.430 mm2,
612.4 kGE, fmax ss 303.2 / tt 463.3 MHz; GLS zero delay and tt SDF (image 0) bit-exact, cycles = RTL, 0 timing
violations; `power.sh -o power_v2 -e qa2_w3.3 sdf` + `compare.py sdf 2.5`: **231.0 mW, 92.4 uJ / inference** at
400 MHz (v1 308.4 mW, 123.3 uJ): macro deselected clocks 60.5 -> 0 mW, act macro reads 6.16 -> 2.83 / cycle;
PE-internal breakdown in section 5 (`power/pe_power.tcl`).

## v3: two blocks per PE per cycle, Kb = 2 (`compile3/`, `hw3/`, `impl/v3/`; [results/v3.md](results/v3.md))

ARCH.md section "v3 (implemented)".  Per step a PE takes the blocks of input groups 2j and 2j + 1 (one 128-b pair
word per row: 2 x 512 x 64 rf macros per bank, 48 in total; even / odd weight halves of 3 x 4096 x 80 read at the
same address) and adds `acc + 4 trit terms` as one fused sum (`hw3/rtl/qa_pe.sv`, `u_acc`); the drain takes 2
columns per read into a 16-lane PPU (20-b v, 20 x 31 multipliers).  v2 modules reused unchanged: `qa_seq`,
`qa_sram`, `qa_bankmem`.

| file | contents |
|---|---|
| `compile3/layout.py` | pair layout (128-b words as (lo, hi) uint64), AGU / kw window on pairs (v2 functions on a pair view), int16 R byte-plane order |
| `compile3/program.py` | `from_v2`: re-pack of the v2 program (even / odd weight words, FC in the even half), v3 proofs (\|d acc + bias\| < 2^19, \|bias\| < 2^19, capacity) |
| `compile3/golden.py`, `export.py`, `main.py`, `test_compile.py` | v3 golden (GEMM + literal 4-term path through the 128-b window), cycle MODEL, `$readmemh` images, CLI, unit tests |
| `hw3/rtl/*` | v3 RTL: `qa_pkg`, `qa_pe` (4 rotators + `qa_pe_acc4`), `qa_array`, `qa_xbar` (128-b window), `qa_agu` (pair loop), `qa_drain` (2 columns / read), `qa_ppu(_lane)` (16 lanes, 20-b v), `qa_head` (half select), `qa_actmem` (48 halves), `qa_host`, `qa_top`; file list `qc18acc.f` |
| `hw3/tech/*` | `qa_sram_tech.sv` (512x64 -> `qa_act_512x64m4`), `qc18acc_tech.f`, `macros_sim.f` |
| `hw3/tb/*`, `hw3/sim/*` | full-network TB, `tb_pe`, mini program; `run_rtl.sh`, `run_unit.sh`, `cycles.py` |
| `impl/v3/` | `sweep.txt` / `sweep_result.txt` (act macro shapes), `macros.txt` |
| `power/compare3.py` | v2 vs v3 tables (energy, blocks, macros, area, fmax, PE groups per QC block, predictions) |

```bash
python3 -m qc18acc.compile3.test_compile                                        # unit tests
CUDA_VISIBLE_DEVICES=0 python3 -m qc18acc.compile3.main --n 1000 --literal 4 --acc   # proofs, cycle model, bit-exact, 10k acc
qc18acc/hw3/sim/run_unit.sh mini                                                # iverilog: tb_pe + mini program
qc18acc/hw3/sim/run_rtl.sh usask 0 4                                            # VCS RTL images 0..3 (QC_TECH=1: macro models)
ssh <host> 'cd /tmp/ckp908/qc18acc/repo && QA_V=3 qc18acc/impl/run.sh macros'  # 512x64 act macro views (~2 min)
ssh <host> 'cd /tmp/ckp908/qc18acc/repo && QA_V=3 qc18acc/impl/run.sh all 3.3 qa3_w3.3'   # DC + PT ss/tt/ff (~25 min)
QA_V=3 qc18acc/gls/run_gls.sh start <host> qa3_w3.3 0 1                         # GLS zero delay + SAIF (~18 min); then check
QA_V=3 qc18acc/gls/run_gls.sh sdf <host> qa3_w3.3                               # tt SDF + ideal-clock view (call until listed)
QA_V=3 QA_SDF=1 qc18acc/gls/run_gls.sh start <host> qa3_w3.3 0 1                # tt-SDF GLS (~80 min); then check
QA_V=3 qc18acc/power/power.sh -H <host> -o power_v3 -e qa3_w3.3 sdf             # PTPX + PE groups + macro model (also zd)
QA_V=3 python3 qc18acc/power/energy.py qc18acc/results/power_v3; python3 qc18acc/power/compare3.py sdf 2.5
```

Results (labels as in results/v3.md: measured / synthesis estimate / model): golden bit-exact 1000 images, 10k
test 91.33 % (= v2); VCS RTL images 0..3 and GLS zero delay + tt SDF (image 0, 0 timing violations) bit-exact,
**81 438 cycles / image** (v2 159 982, x0.509; model 84 560); `qa3_w3.3` **6.514 mm2**, logic **816.4 kGE** (PE 7.92
kGE), fmax ss 303.2 / tt 463.4 / ff 662.0 MHz (same head-FC critical path as v2); at 400 MHz tt **336.2 mW,
68.5 uJ / inference** (v2 231.0 mW, 92.4 uJ; predicted ~70 uJ), PE array energy per QC block x0.684 (predicted
x0.7), 4 912 inferences / s.

## Array ablation: QC vs TERNARY vs INT8 PE (`ablation/`, results [results/ablation.md](results/ablation.md))

Three standalone 8x8 arrays with the v2 geometry, input pipeline register, accumulate / shadow / drain structure and
dataflow (one 8x8 block per PE per cycle); only the PE and the weight width per column differ: QC = `hw/rtl/qa_array`
+ `qa_pe` unchanged (10 b), TERNARY = 64 trits (128 b, 8 trit-selects + adder tree per lane, 21-b accumulator =
worst case of an arbitrary ternary 3x3x512 conv), INT8 = 64 int8 (512 b, 8 signed 8x8 multipliers + adder tree per
lane, 32-b accumulator) (`ablation/rtl/`, tops `qab_top_<v>`).  Stream: the real v2 array inputs of s8kd_s0 image 0
for blocks.3.c1 (K = 144, 16 tiles) and blocks.7.c1 (K = 576, 4 tiles), 2304 steps each; QC / TERNARY with the
s8kd blocks, INT8 with dense_s0 (BN folded, per-channel int8) and the s8kd blocks as int8 (control).

```bash
qc18acc/ablation/run.sh vec            # vectors + numpy reference (GPU 0, ~10 s) -> /tmp/root/qc18acc/ablation/vec
qc18acc/ablation/run.sh rtl            # Verilator RTL check, 8 points
qc18acc/ablation/run.sh sync           # git pull on the hosts (qc: usask, tern: tau5, int8: tau1), rsync vectors
qc18acc/ablation/run.sh start syn      # DC 3.3 ns + PT ss/tt/ff (status: run.sh status syn); QAB_PERIOD=2.0 remote.sh syn <v>: fmax probe
qc18acc/ablation/run.sh start sdf      # DC tt SDF + ideal-clock view
qc18acc/ablation/run.sh start gls      # VCS tt-SDF GLS 2.5 ns, bit-exact check, SAIF of the busy window
                                       # (on the host: remote.sh gls <v> compiles, remote.sh glsrun <v> <point> runs points in parallel)
qc18acc/ablation/run.sh start power    # PT PX tt; QAB_ZD=1 remote.sh gls|glsrun|power: zero-delay (glitch-free) reference
qc18acc/ablation/run.sh fetch && qc18acc/ablation/run.sh report    # -> results/ablation.md, results/ablation/
```

Results (details, assumptions and caveats in [results/ablation.md](results/ablation.md)): all 8 points bit-exact in
RTL, tt-SDF GLS (0 timing violations) and zero-delay GLS.  Array kGE QC 393.7 / TERNARY 513.1 / INT8 2281.2 (6.13 /
7.99 / 35.2 kGE per PE); all close 3.3 ns at ss (2.0-ns probe: ss 495 / 466 / 351 MHz).  Array energy per block-op
(64 MACs) L2 / L4: QC 7.22 / 3.54 pJ, TERNARY 8.15 / 3.88, INT8 (dense_s0 weights) 53.3 / 50.4, INT8 with the s8kd
blocks 22.7 / 20.1.  System MODEL per inference: on-chip weight SRAM QC 86 / TERNARY 179 / INT8 861 uJ and 6.2 / 28.6 /
103.5 mm2; DRAM-streamed weights (dense = lower bound) 121 / 535 / 2283 uJ at 20 pJ/b.  The PE itself (TERNARY -> QC)
gains only ~1.2x; the QC advantage is weight storage / traffic (80 vs 1024 b per step, 0.22 vs 2.8 MB) plus
ternary-vs-int8 arithmetic.

## Place & route, OpenROAD (`pnr/`, results [results/pnr.md](results/pnr.md))

`qc18acc/pnr/run.sh pnr <tag>` (flow/tsmc65/pnr with `qa.cfg`: tiered macro floorplan, macro PDN, IO, post-CTS /
post-GRT repair), `run.sh pt <tag>` (PrimeTime ss / tt with the def2spef SPEF, reg2reg fmax), `power.sh -t <tag>
<period>` (PTPX tt with the v2 SDF SAIF flattened onto the routed netlist, `saif_flat.py`; macro datatable model),
`report.py <period>`.  Result (run qa_t1): die 8.858 mm2, 255 DRC markers, 192 antenna nets, post-route fmax
ss 172.5 / tt 288.3 MHz (reg2reg; pre-route 303 / 463), 272.2 mW = 152.4 uJ / inference at 286 MHz tt (clock tree
17.7 %, SAIF annotation 89 %), post-CTS and routed-netlist GLS bit-exact.  Low-voltage point: [results/lowv.md](results/lowv.md).
