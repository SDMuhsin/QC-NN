#!/usr/bin/env bash
# One command per final model: train it (200 epochs, test evaluated once at the end), or take the
# trained checkpoint (qc/fetch.sh) through export -> int8 (nn/quant) -> float + int8 QC verification.
#   qc/final.sh train  {dense|s2|s4|s8|u2|u4|u8|s4w2|s8w2}   (u* need the dense run first: KD teacher)
#   qc/final.sh int8   {s2|s4|s8|u2|u4|u8}
#   qc/final.sh stats                                         (-> qc/results/*.md)
# Runs live in $QC_RUNS (default /tmp/$USER/qc/final), never inside the repo.  GPU: CUDA_VISIBLE_DEVICES.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
R=${QC_RUNS:-/tmp/$USER/qc/final}
S="--mode signed --method qat --thr 0.5 --wd 5e-5"
U="--mode unsigned --method staged --stages 0.2,0.2,0.6 --thr 0.5 --kd 0.5 --teacher $R/dense/best.pt"
declare -A CFG=([dense]="--mode dense" [s2]="$S --b 2" [s4]="$S --b 4" [s8]="$S --b 8"
                [u2]="$U --b 2" [u4]="$U --b 4" [u8]="$U --b 8" [s4w2]="$S --b 4 --width 2" [s8w2]="$S --b 8 --width 2")
case $1 in
  train) mkdir -p "$R/$2"
         python3 -m qc.train ${CFG[$2]} --epochs 200 --view hwc --test 1 --out "$R/$2" 2>&1 | tee "$R/$2/train.log"
         [ "$2" = dense ] || python3 -m qc.verify "$R/$2/best.pt" | tee "$R/$2/verify.txt" ;;
  int8)  mkdir -p "$R/export" "$R/int8"
         python3 -m qc.verify "$R/$2/best.pt"
         python3 -m qc.export "$R/$2/best.pt" --out "$R/export/$2.npz"
         python3 -m nn.quant.quantize --params "$R/export/$2.npz" --wgran channel --wq 1 --out "$R/int8/$2.pt"
         python3 -m qc.verify_int8 "$R/$2/best.pt" "$R/int8/$2.pt" ;;
  stats) python3 -m qc.stats "$R"/{s2,s4,s8,u2,u4,u8}/best.pt --int8 "$R/int8" ;;
  *) echo "usage: $0 train|int8 NAME | stats" >&2; exit 2 ;;
esac
