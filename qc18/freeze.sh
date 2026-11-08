#!/bin/bash
# Structure-freeze test: hard v fixed after epoch E (--freeze-v-epoch, 0 = off) of the 60-epoch b=8 signed AdamW
# --qwd 0.1 recipe, seeds 0/1, val only -> /tmp/$USER/qc18/freeze/<name>.  E=off runs save per-epoch v (--snap 1)
# for the flip fraction after epoch E.  One job per line; run with a queue, e.g.
#   grep '^CUDA' qc18/freeze.sh | xargs -P 1 -I{} bash -c {}
P="python3 -m qc18.train --epochs 60 --test 0 --mode signed --b 8 --estimator ste --qwd 0.1"; O=/tmp/${USER:-$(whoami)}/qc18/freeze
CUDA_VISIBLE_DEVICES=0 $P --seed 0 --snap 1 --snap-ckpt "" --snap-steps "" --out $O/off_s0
CUDA_VISIBLE_DEVICES=0 $P --seed 0 --freeze-v-epoch 15 --out $O/e15_s0
CUDA_VISIBLE_DEVICES=0 $P --seed 0 --freeze-v-epoch 30 --out $O/e30_s0
CUDA_VISIBLE_DEVICES=0 $P --seed 0 --freeze-v-epoch 45 --out $O/e45_s0
CUDA_VISIBLE_DEVICES=0 $P --seed 1 --snap 1 --snap-ckpt "" --snap-steps "" --out $O/off_s1
CUDA_VISIBLE_DEVICES=0 $P --seed 1 --freeze-v-epoch 15 --out $O/e15_s1
CUDA_VISIBLE_DEVICES=0 $P --seed 1 --freeze-v-epoch 30 --out $O/e30_s1
CUDA_VISIBLE_DEVICES=0 $P --seed 1 --freeze-v-epoch 45 --out $O/e45_s1
