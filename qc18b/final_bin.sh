#!/bin/bash
# Final binary-activation models (200 epochs, val-only selection; the test set is evaluated once, by `verify`).
#   qc18b/final_bin.sh train NAME SEED   -> /tmp/$USER/qc18b/final_bin/<NAME>_s<SEED>
#   qc18b/final_bin.sh verify NAME SEED  -> <run>/verify.txt (folded fp64, QC proof, val + test once)
#   qc18b/final_bin.sh int NAME SEED     -> <run>/intbin.txt (integer reference, val + test)
# NAME: bin   = every non-stem QC conv input 1-bit
#       e6    = bin, except block 6 (c1, sc, c2 inputs) 8-bit / FP          <- meets the <= 5 pt target
# Needs the FP-activation finals of qc18b/final.sh: dense_s0 (KD teacher) and s8kd_s<SEED> (init).
set -eo pipefail
cd "$(dirname "$0")/.."
CMD=$1 NAME=$2 SEED=${3:-0}
U=${USER:-$(whoami)}; F=/tmp/$U/qc18b/final; RUN=/tmp/$U/qc18b/final_bin/${NAME}_s$SEED
export CUDA_VISIBLE_DEVICES=0
R="--mode signed --b 8 --estimator ste --qwd 0.1 --kd 0.5 --kd-t 4 --teacher $F/dense_s0/best.pt
   --binact 1 --preact 1 --arch qc18 --ste clip --ste-scale 0.6 --epochs 200 --init $F/s8kd_s$SEED/best.pt"
case $NAME in
  bin) ;;
  e6)  R="$R --fp-blocks 6" ;;
  *) echo "unknown NAME $NAME"; exit 2 ;;
esac
case $CMD in
  train)  mkdir -p $RUN; python3 -m qc18b.train_bin $R --test 0 --seed $SEED --out $RUN 2>&1 | tee $RUN/train.log ;;
  verify) python3 -m qc18b.verify_bin $RUN/best.pt --test 2>&1 | tee $RUN/verify.txt ;;
  int)    python3 -m qc18b.int_bin $RUN/best.pt --test 2>&1 | tee $RUN/intbin.txt ;;
  *) echo "usage: $0 train|verify|int NAME [SEED]"; exit 2 ;;
esac
