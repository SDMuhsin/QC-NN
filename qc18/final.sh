#!/bin/bash
# Final models (200 epochs, val-only training; the test set is evaluated exactly once, by `verify`).
#   qc18/final.sh train NAME [SEED]   -> /tmp/$USER/qc18/final/<NAME>_s<SEED>
#   qc18/final.sh verify NAME [SEED]  -> <run>/verify.txt (QC: folded verified network on val + test; dense: test acc)
# NAME: dense | s2 s4 s8 (signed, ste, AdamW 0.1) | u2 u4 u8 (unsigned, +-1 BN gamma, sparse init k=2)
#       | s2kd s4kd s8kd (signed + distillation from dense_s0)
set -eo pipefail
cd "$(dirname "$0")/.."
CMD=$1 NAME=$2 SEED=${3:-0}
F=/tmp/${USER:-$(whoami)}/qc18/final
RUN=$F/${NAME}_s$SEED
export CUDA_VISIBLE_DEVICES=0
Q="--estimator ste --qwd 0.1"
case $NAME in
  dense)        R="--mode dense" ;;
  s[248])       R="--mode signed --b ${NAME#s} $Q" ;;
  u[248])       R="--mode unsigned --b ${NAME#u} $Q --bn-sign 1 --qinit-k 2" ;;
  s[248]kd)     B=${NAME#s}; R="--mode signed --b ${B%kd} $Q --kd 0.5 --kd-t 4 --teacher $F/dense_s0/best.pt" ;;
  *) echo "unknown NAME $NAME"; exit 2 ;;
esac
case $CMD in
  train)  python3 -m qc18.train $R --epochs 200 --test 0 --seed $SEED --out $RUN ;;
  verify)
    if [ "$NAME" = dense ]; then
      python3 -c "
import sys, torch
from qc18.data import split, test
from qc18.train import accuracy
from qc18.verify import load
torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
ck, m = load(sys.argv[1], 'cuda')
print(f'{sys.argv[1]}: dense, epoch {ck[\"epoch\"]}, checkpoint val {100 * ck[\"val\"]:.2f} %')
print(f'val accuracy (fp32) {100 * accuracy(m, *split(\"cuda\")[1]):.2f} %')
print(f'test accuracy (fp32) {100 * accuracy(m, *test(\"cuda\")):.2f} %')" $RUN/best.pt 2>&1 | tee $RUN/verify.txt
    else
      python3 -m qc18.verify $RUN/best.pt --test 2>&1 | tee $RUN/verify.txt
    fi ;;
  *) echo "usage: $0 train|verify NAME [SEED]"; exit 2 ;;
esac
