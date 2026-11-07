#!/usr/bin/env bash
# Download the trained QC ResNet-8 checkpoints (kept out of git) into $QC_RUNS (default /tmp/$USER/qc/final):
#   {s2,s4,s8,u2,u4,u8,s4w2,s8w2}/{best.pt,metrics.json,verify.txt}  (release asset qc-v1 of this repo)
# and the CIFAR-10 / Keras inputs via nn/fetch.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
nn/fetch.sh >/dev/null
R=${QC_RUNS:-/tmp/$USER/qc/final}; mkdir -p "$R"
URL=https://github.com/SDMuhsin/QC-NN/releases/download/qc-v1/qc_resnet8_v1.tar.gz
T=$(mktemp -d); curl -sSfL -o "$T/w.tgz" "$URL"
echo "531d97fbb4ec0f2dfe82a88df791703de67be840c000afcde077093a7b94b703  $T/w.tgz" | sha256sum -c -
tar xzf "$T/w.tgz" -C "$T" && cp -r "$T"/qc_resnet8_v1/* "$R"/ && rm -rf "$T"
ls "$R"
