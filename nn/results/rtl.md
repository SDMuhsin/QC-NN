# ResNet-8 on the KUL GeMMX cluster: full-SoC RTL simulation (phase 2)

The complete ResNet-8 (CIFAR-10, int8) runs in RTL in the full chimera SoC (CVA6 host, memory island, KUL
cluster = SNAX GeMMX + 2 Snitch cores) on Questa 2022.1. The cluster's logits and every step's output are compared
with the PyTorch integer reference (`nn.quant.quantize.IntResNet8`).

## Result

| | |
|---|---|
| test images (CIFAR-10 test 0..29, 3 runs of 10 on tau1 / tau5 / usask) | **30 / 30 logits bit-exact**, 30 / 30 step checksums exact, 29 / 30 correctly classified |
| per-layer byte compare (`-DNN_FULL_CHECK`, image 0) | every byte of all 13 step outputs matches |
| cycles / image (cluster clock, mean of 30) | **401 698** (min 401 264, max 404 973 for the first image: cold icache) |
| latency at the synthesised fmax (`kul_w4.2`, WLM, pre-CTS) | **tt 353.7 MHz: 1.136 ms**, ss 229.3 MHz: 1.752 ms (TB clock 500 MHz: 0.80 ms) |
| GeMMX array utilisation while busy (counter) | **72.7 %** of cycles fire (25 856 fires / 35 580 busy); 68.6 % useful MACs (conv0 pads Cin 3 to 8) |
| GeMMX utilisation over the whole image | 6.4 % fires / cycle (busy 8.9 % of the image); effective 2 x 12.5 M MAC / 1.136 ms = 22 GOPS at tt |

Logs: `rtl_logs/` (`all_30.txt` combined, one summary + decoded `nn_result` JSON per run).

## Cycle breakdown (mean over 30 images)

| part | cycles | share | notes |
|---|---:|---:|---|
| GeMMX convs (9 calls) | 63 513 | 15.8 % | busy 35 580, rest: border fills, CSR programming (from TCDM), DMA waits |
| residual adds (3, on both cores) | 300 555 | 74.8 % | 28 672 elements, ~18.5 cycles / element / core |
| pool + FC (core 0) | 35 305 | 8.8 % | |
| input DMA (Snitch iDMA, memory island -> TCDM) | 2 325 | 0.6 % | 10.7 KiB; weight DMAs are hidden behind the previous step |
| total | 401 698 | | checksums / compares after each step are excluded |

| step | cycles | GeMMX busy | streamer busy | fires | fires / busy |
|---|---:|---:|---:|---:|---:|
| conv0 3x3 3->16, 32x32 | 7 061 | 3 050 | 3 051 | 2 304 | 75.5 % |
| conv1 3x3 16->16, 32x32 | 10 116 | 6 162 | 6 163 | 4 608 | 74.8 % |
| conv2 3x3 16->16, 32x32 | 8 424 | 6 180 | 6 181 | 4 608 | 74.6 % |
| add1 | 163 279 | | | | |
| conv3 3x3/s2 16->32 | 7 390 | 3 231 | 3 232 | 2 304 | 71.3 % |
| conv5 1x1/s2 16->32 | 3 281 | 1 036 | 1 037 | 256 | 24.7 % |
| conv4 3x3 32->32, 16x16 | 8 477 | 6 242 | 6 243 | 4 608 | 73.8 % |
| add2 | 88 522 | | | | |
| conv6 3x3/s2 32->64 | 7 677 | 3 084 | 3 085 | 2 304 | 74.7 % |
| conv8 1x1/s2 32->64 | 2 778 | 529 | 530 | 256 | 48.4 % |
| conv7 3x3 64->64, 8x8 | 8 308 | 6 066 | 6 067 | 4 608 | 76.0 % |
| add3 | 48 754 | | | | |
| pool + FC | 35 305 | | | | |

GeMMX busy and streamer busy are the hardware performance counters (read after each call of the first image of each
run). The phase-1 model expected M·N·(K+1) busy cycles (~90-99 %); the measured ~75 % comes from streamer stalls on
the A reader (8 B granular implicit-im2col reads, TCDM bank conflicts). The short 1x1 calls are dominated by the
pipeline fill. The cores are the bottleneck: the KUL core config allows **one outstanding integer load**
(`num_int_outstanding_loads: 1`), so every `lb` costs ~3 cycles. Running the adds on GeMMX (1x1 GEMM with diagonal
weights over channel-concatenated inputs, see `../README.md`) would remove most of the 75 %.

## Bugs found and fixed

1. **D8 writer alignment (compiler).** The GeMMX D8 writer drops address bits [5:0], so every output tile written
   to the interior of a 1-pixel-padded tensor (`(W+2)*8` row pitch) landed up to 56 B early. New layout
   `[C8][H+2][W+8][8]` with the interior at column 8: every D8 tile, row and plane is 64 B aligned; column 7 is
   the left border and column 0 of the next row the right border (`compile/lower.py`, mirrored in the host model,
   which now asserts the alignment, and in the runtime). The A reader is fine with 8 B granular addresses.
2. **KUL cluster icache PMA (hardware config, not RTL logic).** `cfg/snax_KUL_cluster_chimera.hjson` kept the
   upstream `dram` region (0x8000_0000) as the only cacheable region, so every instruction fetch from chimera's
   memory island bypassed the icache (~25 cycles per instruction). Now 0x4800_0000 + 256 KiB. The generated RTL
   differs only in that constant; the `impl/kulcluster` netlists predate it (see below).
3. **Host stack vs. data (link).** The boot-ROM `sp` (0x4800_fff8) is kept by crt0, inside the ELF's data once it
   exceeds 64 KiB. `sw/nn_memisl.ld` puts the CVA6 stack at the top of the memory island.
4. **Test bench (not RTL), for reference:** `vip_chimera_soc.jtag_elf_preload` loops `i <= sec_len`, writing 8
   bytes past the end of every section; the JTAG stub is therefore placed in `.bss`. CVA6's boot ROM uses the
   stack below 0x4801_0000 before the JTAG resume, so the backdoor image is loaded again at the host's first
   instruction (`sim/run_nn.tcl`).

Speed-ups (bit-exact): the residual add uses byte loads, a DMA'd clamp table and three interleaved passes per pixel
(19 -> 10 instructions per element; 22 -> 18.5 cycles; the load-latency limit above caps the gain), and each
conv's `nn_conv_t` travels in its weight blob, so the CSRs are programmed from TCDM (~4 k cycles per conv saved).
Measured on image 0: 471 k -> 434 k -> 407 k cycles.

## How it runs (`../sim/`)

`run_rtl.sh -H <host> -n <images> -f <first> [-- -DNN_FULL_CHECK | -DNN_STOP_AFTER=<step>]` compiles the network
for those test images, builds the ELF, and splits it into the 32 memory-island bank images (`memisl.py`). The
testbench JTAG-loads an 8 B stub (JTAG for 120-240 KiB would take hours of simulated time) and `run_nn.tcl`
`mem load`s the banks. At the end it saves the memory island and the TCDM, and `memisl.py result` decodes
`nn_result` (cycles per step, counters, logits). `summary.py` checks the logits against the reference again.
`tcdm_check.py` compares a tensor or blob in a TCDM dump with the reference (debug, with `NN_STOP_AFTER`). Wall
time: ~1 min boot + ~3 min per image (images run back to back in one ELF; 10 images = 31 min).

## For the gate-level phase

* Netlist: `impl/kulcluster` `kul_w4.2` (and all `kul_*`) were synthesised **before** the PMA fix. They are
  functionally equivalent (same results), but their cores fetch every instruction uncached from the memory
  island, so software (border fills, CSR setup, adds) is ~10-20x slower; GeMMX busy cycles are unaffected.
  For a cycle-matched run, re-synthesise from the current `hw/kulcluster/generated/kulcluster_syn.sv`.
* Heaviest convs: conv1 / conv2 / conv4 / conv7 each have 4 608 fires (2.36 M MACs). conv1 has the longest busy
  window (6 162 cycles), conv7 the best utilisation (76 %, K=72, all 64 channels). RTL busy windows of image 0
  (TB clock 2 ns, `run.log` NN_PROBE lines): conv1 706.3-718.7 us, conv7 1738.1-1750.2 us. On the uncached
  netlist the times shift; use the `gemm_busy` edges (BlockGemm `cstate`) to gate the SAIF window.
* `-DNN_STOP_AFTER=<step>` freezes core 0 after a step and the TCDM is dumped, so a GLS run can stop right after
  the layer of interest; `-n 1` keeps the image short.
