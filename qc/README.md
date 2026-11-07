# qc/ — ResNet-8 (MLPerf Tiny, CIFAR-10) with quasi-cyclic conv weights

Each conv's GEMM matrix `[cout, kh*kw*cin_pad]` (column order `(kh,kw,cin)`, or `(cin,kh,kw)` with
`--view chw`; cin zero-padded to a multiple of b, conv0 3 -> 8) is tiled into b x b blocks; every block is
zero or the sum of at most two distinct cyclically shifted identities (0/1 entries; `signed` mode also
allows -1).  A per-output-channel scale + bias (BatchNorm, folded) follows each conv; the FC is dense float.
Reuses `nn/model` (graph, Keras same padding, CIFAR-10 loader, pretrained `.h5`); input is raw pixels 0..255.

| file | contents |
|---|---|
| `structure.py` | weight <-> matrix views, `expand` (shift coefficients -> matrix), `decompose` (matrix -> shifts, raises if not QC) |
| `layers.py` | `QCConv2d`: real coefficient per (block row, block col, shift) hardened in stages (`staged`, default) or legacy supermask scores (`ste`); modes `unsigned`, `signed`, `dense` |
| `model.py` | `QCResNet8`: the nn/model/resnet8.py graph with QCConv2d + BN (incl. conv5/conv8 shortcuts) |
| `train.py` | one experiment per command; 45k/5k train/val split (seed 0), best-val checkpoint, test once at the end |
| `verify.py` | folds BN, extracts each exact conv matrix, proves QC via `decompose`, re-evaluates the folded net; exit 1 on failure |
| `test_structure.py` | random QC matrices round-trip, non-QC matrices are rejected |

Training (`--method staged`, default): one SGD nesterov + cosine run split by `--stages fA,fB,fC`:
A real block-circulant coefficients (all b shifts); B magnitude pruning per block b -> 2 shifts (linear over
the B epochs, then frozen); C ramp to hard coefficients (STE on the real ones) over `--ramp` of C, then hard.
Hard = 1 (unsigned) / sign (signed) if |coef| > `--thr` x mean |kept coef| of the block row, else 0 (the
per-row scale is absorbed by BN).  BN statistics are recalibrated on train data before every hard-epoch val
and at the end.  Only hard epochs are checkpointed.  Legacy `--method ste`: Adam on scores (`--score-lr`).
`--method qat`: hard coefficients in every forward pass from step 0 (same quantizer), STE on the latent real
coefficients (`--ste-clip`), Adam on them (`--qat-lr`, cosine, no weight decay), SGD for BN/FC; top-2 mask
recomputed from the latent magnitudes every step for the first `--freeze` of the run, then frozen.
`--soft F` (qat): first F of the run real-valued (two-stage, lr restarts); `--clamp0 1`: unsigned latent >= 0.
`--teacher PATH --kd A`: distill from a dense qc.train checkpoint (the Keras model has seen the val split).
`--init PATH`: start from a qc.train checkpoint (dense: projected onto block-circulant).
fp32 for QC (bf16 for dense), torch.compile, GPU-resident data and augmentation (crop pad 4, h-flip).

```bash
python3 -m qc.test_structure
CUDA_VISIBLE_DEVICES=0 python3 -m qc.train --mode dense    --epochs 200 --out /tmp/$USER/qc/runs/dense
CUDA_VISIBLE_DEVICES=0 python3 -m qc.train --mode unsigned --b 8 --epochs 200 --stages 0.2,0.2,0.6 --thr 0.5 --out /tmp/$USER/qc/runs/u8
CUDA_VISIBLE_DEVICES=0 python3 -m qc.train --mode signed   --b 8 --epochs 200 --stages 0.2,0.2,0.6 --thr 0.5 --out /tmp/$USER/qc/runs/s8 \
    [--init dense|PATH] [--kd 0.5 --kd-t 4 [--teacher PATH]] [--view chw] [--topk 2] [--method ste] [--test 0]
# best recipes at b=4 (val, 2 seeds at 100 epochs): signed qat 74.6/73.2 (200 ep: 74.6), unsigned staged + KD 59.5/60.6 (200 ep: 62.8)
CUDA_VISIBLE_DEVICES=0 python3 -m qc.train --mode signed   --b 4 --epochs 100 --method qat --thr 0.5 --wd 5e-5 --test 0 --out /tmp/$USER/qc/runs/s4
CUDA_VISIBLE_DEVICES=0 python3 -m qc.train --mode unsigned --b 4 --epochs 100 --stages 0.2,0.2,0.6 --thr 0.5 \
    --kd 0.5 --teacher /tmp/$USER/qc/runs/dense/best.pt --test 0 --out /tmp/$USER/qc/runs/u4
python3 -m qc.verify /tmp/$USER/qc/runs/s8/best.pt
```
Runs, checkpoints and data never go inside the repo (`--out` must be outside it).
