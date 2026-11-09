# qc18acc/ — QC18-ACC: accelerator for the qc18 QC ResNet-18 (b = 8, signed)

Spec: [ARCH.md](ARCH.md) (incl. "Appendix: memory images and descriptors"). Reference network: `qc18/int8.py`
(`IntNet`, integer-exact), model `s8kd` (`/tmp/root/qc18/final/s8kd_s0/best.pt`, see `qc18/fetch.sh`).

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
| `rtl/qa_agu.sv` | step generator (og, tile, kh, kw, cb), tap offset, per-bank addresses, padding mask, weight address, shadow-capture stall |
| `rtl/qa_xbar.sv` | S2 -> S3: bank-to-row rotation + mask, code register |
| `rtl/qa_pe.sv`, `rtl/qa_array.sv` | QC block PE (2 rotators, trits, 8 x 20-b acc, shadow), 8 x 8 array with column shadow chains |
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

Result (VCS S-2021.09, images 0..3): RESULT PASS, all 10 int32 logits and all 20 stored maps bit-exact per image.
159 982 cycles / image START..DONE (model 162 640, -1.6 %); array busy 85.2 %, AGU stall 20 690, param load 4 800.
Passes > 5 % off the model: blocks.6.c1 -8.3 % (K = 288 > drain + param load, so the 64-cycle param load per og is
hidden behind the next tile; same effect -4.4 % in blocks.7) and the head -48 % (868 vs the 1680 estimate: 8 pixel
words per cycle and pool of group cb + 1 overlapped with the FC of group cb).
