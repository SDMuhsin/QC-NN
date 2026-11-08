#!/usr/bin/env bash
# Download the final qc18 ResNet-18 checkpoints (kept out of git) into $QC18_RUNS (default /tmp/$USER/qc18/final):
#   <NAME>_s<SEED>/{best.pt,metrics.json,verify.txt,int8.txt}  (int8.txt absent for dense; release asset qc18-v1)
# QC18_TARBALL=path uses a local copy of qc18-final.tar.gz instead (built by qc18/pack.sh).
# The tarball is checked against qc18/final.sha256 (written by qc18/pack.sh).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
R=${QC18_RUNS:-/tmp/${USER:-$(whoami)}/qc18/final}; mkdir -p "$R"
URL=https://github.com/SDMuhsin/QC-NN/releases/download/qc18-v1/qc18-final.tar.gz
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
if [ -n "${QC18_TARBALL:-}" ]; then cp "$QC18_TARBALL" "$T/w.tgz"; else curl -sSfL -o "$T/w.tgz" "$URL"; fi
echo "$(cut -d' ' -f1 qc18/final.sha256)  $T/w.tgz" | sha256sum -c -
tar xzf "$T/w.tgz" -C "$T" && cp -r "$T"/qc18-final/* "$R"/
ls "$R"
