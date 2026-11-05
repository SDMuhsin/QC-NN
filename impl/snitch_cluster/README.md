# impl/snitch_cluster: chimera's Snitch cluster on TSMC 65 nm (DC / PrimeTime)

Two variants of the cluster, both with chimera's cluster parameters (9 cores = 8 compute + 1 DMA, TCDM 128 KiB in
16 banks of 1024 x 64 bit, 64-bit narrow / 512-bit wide AXI, 1 KiB I-cache = 2 sets x 16 lines x 256 bit):

| variant | top | sources | role |
|---|---|---|---|
| `fp` (default) | `snitch_cluster_wrapper` | `sim/cfg/chimera_fp.hjson`: the clustergen wrapper and the snitch_cluster workspace of `sim/` (same RTL the NN workloads run on) | **primary result** |
| `chimera` | `qc_snitch_cluster_top` (`rtl/`) | `third_party/chimera`: `chimera_cluster` with `ChimeraCfg[0]`, slot 4 (9 cores) | chimera-exact, integer-only (no FPU / SSR / FREP) |

The difference: chimera leaves `RVF/RVD/Xssr/Xfrep` at 0, the fp config keeps the upstream compute cores
(rv32imafd + SSR + FREP + SIMD FP).  The `chimera` top also contains chimera's narrow / cluster AXI adapters
(two clocks, axi_cdc); the `fp` top is the bare snitch_cluster (one clock) as the testbench uses it.

## Files

| file | what |
|---|---|
| `gen_flist.sh fp\|chimera` | bender -> `flist/<variant>.f` (paths relative to `$QC_ROOT`); the DC work-arounds are documented in its header |
| `fp.f`, `chimera.f` | design file lists: `hw/tech/tsmc65/tsmc65.f` (tech overlay) + `flist/<variant>.f` (+ top) |
| `sync_src.sh` | flow / hw / impl and the listed sources to the server work tree (`QC_HOST`, `QC_WIP`) |
| `constraints.sdc` | clocks, IO, reset / static-input false paths (`QC_SDC`) |
| `dc_hook.tcl`, `pt_hook.tcl` | DC: macros dont_touch, elaboration-only mode; PT: per-clock WNS / fmax, macro area, vectorless power |
| `run.sh` | `elab`, `syn`, `pt`, `summary`, `all` on the server (`QC_VARIANT=fp\|chimera`) |
| `summarize.py` | `results/<tag>/{area,timing,netlist}.txt` from the run directory |
| `results/` | the short summaries (tracked); full reports stay on the server |

The SRAM macros (`hw/tech/tsmc65/macros.txt`, views from `flow/tsmc65/sram/mc_gen.sh gen`, host-local
`/tmp/$USER/qcnn/macros`, `hw/tech/tsmc65/macros.manifest`) must exist on the host that runs DC / PT.

```sh
QC_HOST=tau5 QC_WIP=qcnn/wip_local impl/snitch_cluster/sync_src.sh      # local
cd ~/qcnn/wip_local && flow/tsmc65/sram/mc_gen.sh gen hw/tech/tsmc65/macros.txt   # server, once per host
nohup impl/snitch_cluster/run.sh all 2.0 > /tmp/$USER/qcnn/build/fp_p2.0.log 2>&1 &   # server
```

`qcnn/wip_local` in the (shared, full) NFS home is a symlink to `/tmp/$USER/qcnn/tree`, so every host has its own
host-local tree; builds go to `QC_BUILD=/tmp/$USER/qcnn/build`.

## Memories (hw/tech/tsmc65/tc_sram.sv)

| array | instances | implementation |
|---|---|---|
| TCDM bank 1024 x 64, byte enables | 16 | `qc_sp_1024x64m8` HD-SRAM, mux 8, byte write mask, 646.5 x 177.6 um |
| I-cache data set 16 x 256 | 2 | 2 x `qc_rf_16x128m1` register file each, 225.8 x 87.0 um |
| I-cache tag set 16 x 41 | 2 | flip-flops (smaller than a 16 x 44 RF macro) |
| other tc_sram shapes | - | flip-flops |

Macro margin pins (EMA) tied to 000, retention inactive; a hold register per macro port keeps the tc_sram
read-data contract (the macros are write-through).  Clock cells (`tc_clk.sv`): CKLNQD1 ICG, CKMUX2D1, CK* gates.

## Results (DC wire-load, ss 0.9 V 125 C; PrimeTime ss / tt / ff; pre-CTS, ideal clocks, no parasitics)

Full numbers in `results/<tag>/{area,timing,netlist}.txt`.  fmax = 1 / (period - WNS) of the worst clu_clk path.

| tag | variant | period | total mm2 | logic mm2 (kGE) | macros mm2 | fmax ss / tt / ff MHz | power tt (vectorless) |
|---|---|---|---|---|---|---|---|
| **fp_p4.0** | fp | 4.0 ns | **5.80** | 3.89 (2700) | 1.92 | **250** / 382 / 538 | 68 mW @ 250 MHz |
| fp_p2.0 | fp | 2.0 ns (over-constrained) | 5.93 | 4.01 (2787) | 1.92 | 257 / 394 / 554 | 119 mW @ 500 MHz |
| snc_p2.0 | chimera | 2.0 ns | 2.98 | 1.07 (742) | 1.92 | 412 / 618 / 849 (soc_clk 436 / 591 / 677) | 74 mW @ 500 MHz |

* fp: the FPUs dominate (each compute core ~0.37 mm2, of which the FP subsystem ~0.28 mm2).  fpnew is configured with
  `PipeConfig BEFORE`, so `dc_hook.tcl` enables register retiming for the fpnew designs; the remaining critical
  paths at ss are inside the SIMD FP units (sdotp / cast) after retiming, at tt / ff the FPU sequencer -> SSR FIFO
  paths.  fp_p4.0 meets 4.0 ns at ss (WNS -0.001 ns in PT).
* chimera: worst ss path is the shared multiplier (`snitch_shared_muldiv`); soc_clk paths are the CDC FIFO outputs
  to the ports with 20 % IO delay.
* Hold: about 1300 endpoints at -0.1 to -0.2 ns in every corner, mostly macro input pins (macro hold 0.29 ns at ss),
  with ideal clocks; left to CTS / P&R hold fixing.
* Power: PrimeTime vectorless (toggle 0.1 / cycle, static probability 0.5 on inputs and defaults), no switching
  activity from simulation: an order-of-magnitude estimate only.
* Wire-load mode only (the library's ZeroWireload is selected): topographical mode was not run (an fp DC run is
  3-3.5 h on 8 cores).

Netlists (host-local, `<dir>/<top>.{v,ddc,sdc}`; the macros are black boxes, models in `/tmp/ckp908/qcnn/macros`
on the same host):

| tag | host | dir |
|---|---|---|
| fp_p4.0 (primary) | usask (engr-tau-02L) | `/tmp/ckp908/qcnn/build/syn/fp_p4.0/` |
| fp_p2.0 | tau5 (engr-tau-05L) | `/tmp/ckp908/qcnn/build/syn/fp_p2.0/` |
| snc_p2.0 | usask (engr-tau-02L) | `/tmp/ckp908/qcnn/build/syn/snc_p2.0/` |

The tech overlay alone is checked by `hw/tech/tsmc65/test/run.sh` (VCS, vendor macro models, 20 000 random
operations per shape against a reference model of the tc_sram contract: PASS; a mutant without the hold adapter
fails).
