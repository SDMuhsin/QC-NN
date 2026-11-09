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
