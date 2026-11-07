# s2 on the QC-GeMMX cluster: full-SoC RTL simulation (M2b)

Same flow as `nn/results/rtl.md`: chimera SoC (CVA6 + memory island + KUL cluster) on Questa 2022.1, cluster
clock 2 ns, logits and per-step checksums compared with `nn.quant.quantize.IntResNet8` (s2 int8 model).
QC cluster = `qcacc/hw/gen.sh` (QC GeMM core, 1 x 64 b B reader, per-output-channel requant table in the
RescaleSIMD), one GeMMX call per conv (9 calls, table programmed per call).  Runner: `qcacc/hw/sim/run_rtl_qc.sh`.

## Result

| | |
|---|---|
| test images (CIFAR-10 test 0..29, 3 runs of 10 on usask / tau1 / tau5) | **30 / 30 logits bit-exact**, 30 / 30 step checksums exact, 27 / 30 correctly classified |
| per-layer byte compare (`-DNN_FULL_CHECK`, image 0) | every byte of all 13 step outputs matches |
| cycles / image (cluster clock, mean of 30) | **400 346** (min 399 862, max 404 279); dense baseline 401 698 |
| GeMMX convs (9 calls) | **62 046** cycles (dense 63 513); busy 31 693 for 25 856 fires = **81.6 %** (dense 72.7 %) |
| control: s2 as int8 ternary weights on the **unmodified** base cluster (42 per-group calls), images 0..2 | 3 / 3 bit-exact, **474 310** cycles / image, convs 135 639, busy 36 017 (71.8 %) |
| host checks | schedule model 1000 images bit-exact (qc 9 calls, gemmx 42 calls); native C run 8 images exit 0 (qc, qc + `NN_FULL_CHECK`, gemmx) |
| unit TBs (`qcacc/hw/tb/run.sh`) | QcBlockGemm 209 cases / 29 574 fires bit-exact; RescaleSIMD + table 209 cases (159 with the table, 1..8 groups) / 5 248 tiles bit-exact |

Logs: `rtl_logs/` (`qc_all_30.txt` combined, one summary + decoded `nn_result` JSON per run, control, unit TBs,
host checks).

## Cycle breakdown (mean over 30 images)

| part | cycles | share | dense (nn/results/rtl.md) |
|---|---:|---:|---:|
| GeMMX convs (9 calls) | 62 046 | 15.5 % | 63 513 |
| residual adds (3, on both cores) | 300 593 | 75.1 % | 300 555 |
| pool + FC (core 0) | 35 349 | 8.8 % | 35 305 |
| input DMA | 2 358 | 0.6 % | 2 325 |
| total | 400 346 | | 401 698 |

| step | cycles | GeMMX busy | streamer busy | fires | fires / busy | dense busy |
|---|---:|---:|---:|---:|---:|---:|
| conv0 3x3 3->16, 32x32 | 6 892 | 2 701 | 2 703 | 2 304 | 85.3 % | 3 050 |
| conv1 3x3 16->16, 32x32 | 9 578 | 5 475 | 5 477 | 4 608 | 84.2 % | 6 162 |
| conv2 3x3 16->16, 32x32 | 7 791 | 5 431 | 5 433 | 4 608 | 84.8 % | 6 180 |
| add1 | 163 240 | | | | | |
| conv3 3x3/s2 16->32 | 7 092 | 2 732 | 2 734 | 2 304 | 84.3 % | 3 231 |
| conv5 1x1/s2 16->32 | 3 513 | 1 034 | 1 036 | 256 | 24.8 % | 1 036 |
| conv4 3x3 32->32, 16x16 | 7 983 | 5 509 | 5 511 | 4 608 | 83.6 % | 6 242 |
| add2 | 88 586 | | | | | |
| conv6 3x3/s2 32->64 | 7 723 | 2 693 | 2 695 | 2 304 | 85.5 % | 3 084 |
| conv8 1x1/s2 32->64 | 3 204 | 525 | 527 | 256 | 48.8 % | 529 |
| conv7 3x3 64->64, 8x8 | 8 269 | 5 592 | 5 594 | 4 608 | 82.4 % | 6 066 |
| add3 | 48 766 | | | | | |
| pool + FC | 35 349 | | | | | |

Counters: hardware GeMMX / streamer busy, first image of each run (averaged).  Busy is ~11 % lower than dense
for the same fires; the BlockGemm control is the dense one, so this is most likely the B reader (one 8 B word
per fire on a narrow port instead of 8 x 64 b on the wide ports: fewer stalls; not analysed in detail).  The
control on the base cluster has 36 017 busy for the same fires.  The total is set by the core-side residual adds, as in the dense baseline.

## Call count (why one call per conv)

| run | calls | conv cycles | total / image |
|---|---:|---:|---:|
| M2a: QC cluster, 42 per-group calls (image 0) | 42 | 133 185 | 475 715 |
| control: base cluster, gemmx mode, 42 calls (images 0..2) | 42 | 135 639 | 474 310 |
| **M2b: QC cluster + requant table, 9 calls** (images 0..29) | 9 | **62 046** | **400 346** |

Each extra call costs ~2.2 k cycles outside the busy window (CSR programming from TCDM, border fill, checks);
the table costs up to 81 extra CSR writes per call, which are inside the 9-call total above.

## Notes / open issues

* The table's storage is the 81 CSR-manager registers (2 592 flops; no copy) plus `QcRequantTable` (19-bit
  group counter, 8 lanes x 40 b 8:1 select) - separate modules for the synthesis area report (not done yet).
* The table is read live during a call; software must not rewrite it before the call has finished (nn/sw waits).
* Upstream `PipelinedRescaleSIMD` (also used by the dense cluster) mis-handles output_o back-pressure: its lane
  valid shifts `output_data_reg` without an output handshake (seen in the SIMD unit TB, also with the table
  disabled).  The D8 writer never back-pressures in these runs (all bit-exact); the TB stalls the input only.
* `GEMMX_START/BUSY/PERF` moved to CSR 1124..1126 (start must stay the CSR manager's last register); snRuntime's
  `csrw_ss` switch stops at 1063, so the QC tree's gemmx lib uses literal `csrw`/`csrr` for them.
