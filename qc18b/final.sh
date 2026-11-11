#!/bin/bash
# CIFAR-100 final models, mirroring qc18/final.sh (200 epochs, val-only training; test evaluated once by `verify`).
#   qc18b/final.sh train NAME [SEED]   -> /tmp/$USER/qc18b/final/<NAME>_s<SEED>
#   qc18b/final.sh verify NAME [SEED]  -> <run>/verify.txt (QC: folded verified network on val + test; dense: val + test)
# NAME: dense | s8 (signed b8, ste, AdamW 0.1) | s8kd (s8 + distillation from qc18b dense_s0)
set -eo pipefail
cd "$(dirname "$0")/.."
CMD=$1 NAME=$2 SEED=${3:-0}
F=/tmp/${USER:-$(whoami)}/qc18b/final
RUN=$F/${NAME}_s$SEED
export CUDA_VISIBLE_DEVICES=0
Q="--estimator ste --qwd 0.1"
case $NAME in
  dense) R="--mode dense" ;;
  s8)    R="--mode signed --b 8 $Q" ;;
  s8kd)  R="--mode signed --b 8 $Q --kd 0.5 --kd-t 4 --teacher $F/dense_s0/best.pt" ;;
  *) echo "unknown NAME $NAME"; exit 2 ;;
esac
case $CMD in
  train)  python3 -m qc18b.train $R --epochs 200 --test 0 --seed $SEED --out $RUN ;;
  verify)
    if [ "$NAME" = dense ]; then D=--dense; else D=; fi
    python3 -m qc18b.verify $RUN/best.pt --test $D 2>&1 | tee $RUN/verify.txt ;;
  *) echo "usage: $0 train|verify NAME [SEED]"; exit 2 ;;
esac
