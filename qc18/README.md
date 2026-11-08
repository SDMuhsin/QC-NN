# qc18/ — ResNet-18 (CIFAR-10) with quasi-cyclic conv weights

Every conv (stem, block convs, 1x1 shortcuts) has a GEMM matrix `[cout, kh*kw*cin_pad]` (columns `(kh,kw,cin)`,
cin zero-padded to a multiple of b, stem 3 -> b) whose b x b blocks are zero or a sum of <= 2 distinct cyclic
shifts with entries 0/1 (`unsigned`) or -1/0/1 (`signed`); BN (per-channel scale + bias) after each conv; FC dense.
Reuses `qc.structure` (views, `expand`, `decompose`) and the 45k/5k split + augmentation of `qc.train`.

| file | contents |
|---|---|
| `qcconv.py` | `QCConv2d`: latent theta[R, Cb, b]; forward = exact projection onto V (top-2 shifts above alpha_r/2, stable sort), stored in buffer `v`; backward `ste` (identity) or `gibbs` (Cov_p(v) g / (tau alpha_r), p over all of V) |
| `model.py` | `QCResNet18` (kuangliu layout), every conv a `QCConv2d` + BN (`ConvBN`) |
| `data.py` | GPU split/augmentation (from `qc.train`), mean/std normalisation -> NCHW channels_last |
| `train.py` | one experiment per command; SGD (dense weights, BN, FC) + Adam (theta); tau anneal; bf16, torch.compile; best/last checkpoints, `metrics.json` (loss, train/val acc, time, flip rate) |
| `verify.py` | folds BN, recovers the exact integer M of every conv, proves QC via `decompose`, re-evaluates the folded fp64 network vs the model; exit 1 on failure |
| `test_qcconv.py` | hard projection vs brute force over V, Gibbs backward vs autograd Jacobian, model weights decompose |

Eval mode uses the stored hard `v` (refreshed from theta after every epoch), so the checkpoint is exactly the
evaluated/verified network.  QC val is measured after BN recalibration on 10k train images; eval is fp32.
Runs default to `/tmp/$USER/qc18/runs/<name>` (`--out` must be outside the repo).  `--test 1` evaluates the test
set once at the end (best-val checkpoint); default off.

```bash
python3 -m qc18.test_qcconv
CUDA_VISIBLE_DEVICES=0 python3 -m qc18.train --mode dense --epochs 200
CUDA_VISIBLE_DEVICES=0 python3 -m qc18.train --mode signed   --b 8 --estimator ste   --epochs 200
CUDA_VISIBLE_DEVICES=0 python3 -m qc18.train --mode signed   --b 8 --estimator gibbs --tau0 1 --tau1 0.1 --epochs 200
CUDA_VISIBLE_DEVICES=0 python3 -m qc18.train --mode unsigned --b 2 --estimator gibbs --tau0 1 --tau1 0.1 --epochs 200
#   common options: --bs 128 --lr 0.1 --wd 5e-4 --warmup 2 --qlr 1e-2 --qopt adam|sgd --tau-sched geometric|cosine
#                   --bn-sign 0|1 --qinit-k K --seed 0 --test 0 --out DIR
CUDA_VISIBLE_DEVICES=0 python3 -m qc18.verify /tmp/$USER/qc18/runs/signed_b8_gibbs_s0/best.pt [--test]
```

Speed (A40, bs 128, bf16 + compile): ~8.5 s/epoch dense, ~8-11 s/epoch QC (b=2/8, ste/gibbs), ~6 GB peak;
two runs sharing one GPU each run at ~9-11 s/epoch (single runs are launch-bound).
Note: strict `unsigned` collapses at init (final features rank-1: all-positive weights make every channel the
same common mode after BN); 3-epoch smoke runs stay at ~13 % val.  `signed` trains normally.
Fix (pilot, `pilot.sh`): random +-1 BN gamma (`--bn-sign 1`) breaks the collapse (70 % val, 60 ep); adding a
sparse init (`--qinit-k 2`: 2 active blocks per block row) restores feature rank at init and reaches 85 % val.
