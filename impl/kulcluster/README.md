# impl/kulcluster: KUL cluster (SNAX, GeMMX) on TSMC 65 nm (DC / PrimeTime)

Top `KULCluster_snax_KUL_cluster_wrapper` (what chimera instantiates in its `TARGET_KULCLUSTER` slot), from the
self-contained synthesis pickle `hw/kulcluster/generated/kulcluster_syn.sv` (`hw/kulcluster/flist.sh kul-only`;
regenerate with `hw/kulcluster/gen.sh`).  One clock `clk_i`.  Library tcbn65gplus 200a (CCS), corners
ss = wc 0.9 V 125 C, tt, ff = lt; DC in wire-load mode, PrimeTime pre-CTS (ideal clocks, no parasitics).

## Files

| file | what |
|---|---|
| `macros.txt` | the ARM RF macros (input of `flow/tsmc65/sram/mc_gen.sh gen`), with the shape choice |
| `sweep.txt` | the candidate shapes compared (`mc_gen.sh sweep`) |
| `tech/kul_tc_sram.sv` | `KULCluster_tc_sram` on the macros (TCDM / icache shapes), flip-flops otherwise |
| `gen_src.sh <dir>` | synthesis sources: pickle without its generic `KULCluster_tc_sram` / `KULCluster_tc_clk_*`, prefixed copies of the shared overlay `hw/tech/tsmc65/tc_clk.sv` (clock cells) and of the `tc_sram_qc_hold` / `_ff` helpers of `hw/tech/tsmc65/tc_sram.sv`, file list `kul.f` |
| `constraints.sdc` | clock, IO (20 % of the period), reset / static inputs false paths (`QC_SDC`) |
| `dc_hook.tcl`, `pt_hook.tcl` | DC: macros dont_touch, macro / clock-cell list; PT: fmax, worst paths (all, into / out of macros), vectorless power |
| `run.sh` | `macros`, `elab`, `syn`, `pt`, `summary`, `all` on the server |
| `summarize.py` | `results/<tag>/{area,timing,netlist}.txt`: area per block (GeMMX, cores, DMA, TCDM, interconnect ...), per corner fmax / paths / power |

## Memories

| array | instances | macro |
|---|---|---|
| TCDM bank 512 x 64, byte enables | 32 | `kul_rf_512x64m4` RF, mux 4, byte write mask, 398.0 x 133.3 um |
| I-cache data way 128 x 256 | 2 | 2 x `kul_rf_128x128m1` RF each, 230.7 x 146.8 um |
| I-cache tag way 128 x 39 | 2 | `kul_rf_128x40m1` RF (1 bit padded), 117.2 x 146.8 um |
| other tc_sram shapes | - | flip-flops (none in this configuration) |

EMA tied to 000, RETN inactive, a hold register per macro port keeps the tc_sram read-data contract (write-through
macros).  Clock cells: the design instantiates only `tc_clk_inverter` (icache L0, `EARLY_LATCH = 0`, so no
tc_clk_gating / tc_clk_mux2 instance remains) -> CKND1; DC inserts its own CKLNQD ICGs (`-gate_clock`).

## Run (server, e.g. tau1; build in /tmp, the NFS home is full)

```sh
rsync -a --relative flow/tsmc65 hw/tech impl/kulcluster hw/kulcluster/generated/kulcluster_syn.sv tau1:/tmp/$USER/qcnn_kulsyn/tree/
# site/sram.sh of that tree: QC_MC_OUT=/tmp/$USER/qcnn_kulsyn/macros, QC_MC_SCRATCH=/tmp/$USER/qcnn_kulsyn/mc_scratch
impl/kulcluster/run.sh macros            # ~5 min, views host-local
nohup impl/kulcluster/run.sh all 3.5 > /tmp/$USER/qcnn_kulsyn/build/all_p3.5.log 2>&1 &   # DC ~50 min + PT 3 x 2 min
```

## Results (Nov 2026, tau1)

| tag | DC target (ss) | total mm2 | logic mm2 (kGE) | PT ss WNS / fmax | tt fmax | ff fmax | PT power ss / tt / ff (vectorless, at target) |
|---|---|---|---|---|---|---|---|
| `kul_p2.5` | 2.5 ns | 4.049 | 2.182 (1515) | -1.003 ns / 285.5 MHz | 434.6 MHz | 606.4 MHz | 306 / 361 / 491 mW |
| `kul_p3.5` | 3.5 ns | 3.993 | 2.126 (1476) | -0.017 ns / 284.3 MHz | 433.3 MHz | 605.9 MHz | 223 / 260 / 357 mW |
| `kul_p4.0` | 4.0 ns | 3.957 | 2.090 (1451) | +0.002 ns / 250.1 MHz (met) | 382.8 MHz | 539.9 MHz | 197 / 229 / 316 mW |
| `kul_w3.5` (kit WLM) | 3.5 ns | 4.060 | 2.192 (1523) | -0.697 ns / 238.3 MHz | 364.2 MHz | 515.1 MHz | 235 / 274 / 375 mW |
| **`kul_w4.2`** (kit WLM, P&R netlist) | 4.2 ns | 4.040 | 2.172 (1509) | -0.162 ns / 229.3 MHz | 353.7 MHz | 503.1 MHz | 200 / 231 / 319 mW |

The `kul_p*` runs used the library default wire-load model, which for tcbn65gplus is ZeroWireload (no wire cap); they
are optimistic and undersized (OpenROAD then had to grow the cell area by ~80 % to fix slew / cap).  The `kul_w*`
runs use the kit's area-selected WireAreaLowkCon models (enclosed mode, flow/tsmc65 `QC_WLM_GROUP`).  At 4.2 ns the
WLM netlist still misses ss by 0.16 ns, and its fmax is no better than the 3.5 ns run's, so the target was not
pushed further.

All `kul_*` netlists were synthesised before the icache PMA fix of `hw/kulcluster/cfg` (cached region = memory
island instead of DRAM, see `hw/kulcluster/README.md`).  The only RTL difference is the constant base/mask of that
region in each core's fetch-cacheability compare: the netlists are functionally equivalent to the current RTL, but
their cores fetch uncached from the memory island (much slower software, same GeMMX timing).  Re-synthesise for a
cycle-matched gate-level run of whole programs.

fmax = 1 / (period - WNS) with 0.25 ns setup uncertainty, pre-CTS, wire-load, ideal clocks; tt / ff use the ss-optimised
netlist.  Macros 1.867 mm2 (46.8 %): 32 x `kul_rf_512x64m4` 1.697 mm2, 4 x `kul_rf_128x128m1`, 2 x `kul_rf_128x40m1`.
Block split of `kul_p3.5` (`results/kul_p3.5/area.txt`): GeMMX 0.987 mm2 = 24.7 % of the cluster, 46.4 % of the logic
(GeMM array + SIMD rescale 0.785, streamer 0.194); TCDM interconnect 0.317, AXI xbars / cuts 0.312, xDMA 0.155,
Snitch iDMA 0.134, 2 Snitch cores 0.076, icache 0.243 (0.170 macro).  96.9 % of the registers DC-clock-gated (3440 ICGs).

Critical paths: ss: GeMMX SIMD rescale lane (`BlockGemmRescaleSIMD` zero-point / multiply / shift) -> streamer writer
data buffer, about 3.25 ns of logic.  tt / ff: a combinational chain from core 0's accelerator-request spill register
through the GeMMX CSR mux / streamer / wide and narrow TCDM interconnect into the xDMA reader address generator.
Hold: clean at ss; -0.03 ns on macro D pins at ff (before CTS / hold fixing in P&R).
