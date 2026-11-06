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

## Results (DC wire-load `WireAreaLowkCon` enclosed, ss 0.9 V 125 C; PrimeTime ss / tt / ff; pre-CTS, ideal clocks)

Full numbers in `results/<tag>/{area,timing,netlist}.txt`.  fmax = 1 / (period - WNS) of the worst clu_clk path.
Same SDC (`constraints.sdc`), FPU-only retiming (`dc_hook.tcl`) and macros as the superseded runs below; only the
wire-load model differs (flow commit a9319d6, `flow/tsmc65/README.md` "Wire-load model").

| tag | variant | period | total mm2 | logic mm2 (kGE) | macros mm2 | fmax ss / tt / ff MHz | power tt (vectorless) |
|---|---|---|---|---|---|---|---|
| **fp_p5.0_wlm** | fp | 5.0 ns | **5.93** | 4.01 (2785) | 1.92 | **200** / 309 / 442 | 68 mW @ 200 MHz |
| fp_p4.0_wlm | fp | 4.0 ns (misses at ss: WNS -1.03 ns, 49k endpoints) | 5.99 | 4.08 (2831) | 1.92 | 199 / 309 / 443 | 86 mW @ 250 MHz |

* fp_p5.0_wlm is the primary result: 5.0 ns is met at ss (PT WNS +0.005 ns; DC 0.000).  4.0 ns misses badly, and the
  4.0 ns netlist is not faster (199 MHz): 5.0 ns is the period that just meets.
* Area: each compute core ~0.38 mm2, of which the FP subsystem ~0.29 mm2 (+4 % vs the zero-WLM run, from drive
  strength); logic 2.79 MGE (NAND2 = 1.44 um2).
* **What limits fmax** (PT ss, 5.0 ns netlist): there is no single critical unit.  53 800 paths are within 0.25 ns of
  the worst slack; by endpoint: FP subsystem (scoreboard / regfile / LSU) 16.0k, integer core 11.7k, SSR 8.5k, FPU
  datapaths (fma / sdotp / cast / other) 8.4k, I-cache L0 3.5k, TCDM macro pins 1.5k.  The worst classes in the 4.0 ns
  netlist all end at -1.02 to -1.03 ns, with 70-85 cells per path:
  * FREP sequencer -> FP LSU -> `gen_fpu_i_reqrsp_mux` -> address decode -> TCDM interconnect (stream_xbar arbiter)
    -> ready back to the SSR address generator / FP scoreboard, or forward to the SRAM GWEN: a full core <-> TCDM
    request / grant round trip in one cycle;
  * integer core: pc -> L0 I-cache lookup -> decode -> LSU consistency queue (`gen_caq`) -> dpc / regfile write enable;
  * FPU datapaths after retiming (fma / sdotp) end at the same slack: retiming balanced them to the control paths.
* **Not explained by FPU pipeline depth.** The fpnew settings of `sim/cfg/chimera_fp.hjson` are the upstream
  `default.hjson` ones (snitch_cluster c12ce9b): `lat_comp_fp64 3, fp32 2, fp16 / fp16alt / fp8 / fp8alt 1,
  noncomp 1, conv 2, sdotp 3`, `fpu_pipe_config BEFORE` (identical).  The FPU datapaths are only ~16 % of the
  near-critical endpoints, and the integer core and TCDM paths, which have no FPU pipeline registers, fail together with
  them, so deeper FPU pipelines alone would not raise fmax.  One timing knob differs: `register_fpu_req: false`
  (chimera's `snitch_cluster` default, which chimera never sets because its cluster has no FPU) where upstream
  `default.hjson` has `true`.  It is the cut register on the FP-LSU port of `gen_fpu_i_reqrsp_mux`
  (`snitch_cc.sv`), i.e. on the first path class above; the integer core / I-cache paths would remain.  The design was
  not changed.
* Against the paper (Snitch, Zaruba et al., IEEE TC 2021: GF22, 3.3 MGE, 755 MHz worst case): 2.79 MGE logic is above
  the expected 65 nm range of 1.6-2.6 MGE (this config adds SIMD FP8 / FP16 / sdotp, SSR intersection and indirection);
  200 MHz at ss is below the expected 350-500 MHz.  The gap is not explained by the FPU pipeline (above): it comes
  from the single-cycle core <-> TCDM and fetch -> LSU loops of this config at 65 nm ss.  The wire-load model is not
  the cause either: the topographical run (below) gives the same fmax (198 MHz at ss).
* tt / ff limiters: FREP sequencer -> SSR FIFO paths (same class as above).
* Hold: about 1100-1300 endpoints at -0.07 to -0.13 ns in every corner, mostly macro input pins (macro hold 0.29 ns
  at ss), with ideal clocks; left to CTS / P&R hold fixing.
* Power: PrimeTime vectorless (toggle 0.1 / cycle, static probability 0.5 on inputs and defaults), no switching
  activity from simulation: an order-of-magnitude estimate only.
* Gate-level simulation of fp_p5.0_wlm (zero-delay, gemm_fp64): PASS, 6518 cycles = RTL, retire stream identical to RTL
  on 9/9 harts (`gls/results.txt`).
* Topographical mode (`QC_TOPO=1`, `compile_ultra -spg`, TLU+ RC, 5.0 ns; tag fp_p5.0_topo, 4.2 h, peak 10.9 GB):
  6.02 mm2 total, 4.11 mm2 logic (2853 kGE); PT with the DC topographical parasitic estimate (SPEF): fmax ss / tt / ff
  198 / 311 / 433 MHz (ss WNS -0.04 ns, DC 0.000), power tt 79 mW @ 200 MHz.  It agrees with fp_p5.0_wlm within 1-2 %
  in fmax and area, which confirms the area-selected wire-load model for this block.

### Superseded: zero wire load (ZeroWireload)

These runs used the library's default wire-load selection, which in tcbn65gplus is `ZeroWireload` (no wire
capacitance at all): DC sized for pin loads only, so area and fmax were optimistic (P&R after CTS found ss -8.4 ns on
the fp_p4.0 netlist).  Kept for reference only; do not use these numbers.

| tag | variant | period | total mm2 | logic mm2 (kGE) | macros mm2 | fmax ss / tt / ff MHz | power tt (vectorless) |
|---|---|---|---|---|---|---|---|
| fp_p4.0 (zero WLM, superseded) | fp | 4.0 ns | 5.80 | 3.89 (2700) | 1.92 | 250 / 382 / 538 | 68 mW @ 250 MHz |
| fp_p2.0 (zero WLM, superseded) | fp | 2.0 ns (over-constrained) | 5.93 | 4.01 (2787) | 1.92 | 257 / 394 / 554 | 119 mW @ 500 MHz |
| snc_p2.0 (zero WLM, not re-run) | chimera | 2.0 ns | 2.98 | 1.07 (742) | 1.92 | 412 / 618 / 849 (soc_clk 436 / 591 / 677) | 74 mW @ 500 MHz |

* zero-WLM fp: the remaining critical paths at ss were inside the SIMD FP units (sdotp / cast) after retiming.
* chimera: worst ss path was the shared multiplier (`snitch_shared_muldiv`); soc_clk paths are the CDC FIFO outputs
  to the ports with 20 % IO delay.

Netlists (host-local, `<dir>/<top>.{v,ddc,sdc}`; the macros are black boxes, models in `/tmp/ckp908/qcnn/macros`
on the same host):

| tag | host | dir |
|---|---|---|
| fp_p5.0_wlm (primary) | usask (engr-tau-02L) | `/tmp/ckp908/qcnn/build/syn/fp_p5.0_wlm/` |
| fp_p4.0_wlm | usask (engr-tau-02L) | `/tmp/ckp908/qcnn/build/syn/fp_p4.0_wlm/` |
| fp_p5.0_topo (+ `.spef`) | usask (engr-tau-02L) | `/tmp/ckp908/qcnn/build/syn/fp_p5.0_topo/` |
| fp_p4.0 (zero WLM, superseded) | usask (engr-tau-02L) | `/tmp/ckp908/qcnn/build/syn/fp_p4.0/` |
| fp_p2.0 (zero WLM, superseded) | tau5 (engr-tau-05L) | `/tmp/ckp908/qcnn/build/syn/fp_p2.0/` |
| snc_p2.0 (zero WLM) | usask (engr-tau-02L) | `/tmp/ckp908/qcnn/build/syn/snc_p2.0/` |

`pnr/` and `gls/gls.sh` still default to the superseded fp_p4.0 netlist (`QC_SN_SYN` / `GLS_SYN` select another).

The tech overlay alone is checked by `hw/tech/tsmc65/test/run.sh` (VCS, vendor macro models, 20 000 random
operations per shape against a reference model of the tc_sram contract: PASS; a mutant without the hold adapter
fails).
