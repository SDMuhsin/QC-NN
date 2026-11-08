#!/usr/bin/env bash
# Build the qc18 release tarball from the final runs (see qc18/final.sh):
#   $QC18_RUNS (default /tmp/$USER/qc18/final)/<NAME>_s<SEED>/{best.pt,metrics.json,verify.txt,int8.txt}
#   -> /tmp/$USER/qc18/qc18-final.tar.gz (top dir qc18-final/), and its sha256 -> qc18/final.sha256.
# Every run dir must be finished (best.pt, metrics.json, verify.txt; int8.txt for all but dense); logs and
# last.pt are not packed.  Upload the tarball as release asset qc18-v1/qc18-final.tar.gz (fetched by qc18/fetch.sh).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
U=${USER:-$(whoami)}
F=${QC18_RUNS:-/tmp/$U/qc18/final}
OUT=/tmp/$U/qc18/qc18-final.tar.gz
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/qc18-final"
n=0
for d in "$F"/*_s*/; do
  run=$(basename "$d")
  need="best.pt metrics.json verify.txt"; [[ $run == dense_* ]] || need="$need int8.txt"
  for f in $need; do [ -s "$d/$f" ] || { echo "pack: $run missing $f (unfinished run?)"; exit 1; }; done
  mkdir "$T/qc18-final/$run"
  for f in best.pt metrics.json verify.txt int8.txt; do [ -f "$d/$f" ] && cp "$d/$f" "$T/qc18-final/$run/"; done
  n=$((n + 1))
done
[ $n -gt 0 ] || { echo "pack: no run dirs in $F"; exit 1; }
tar czf "$OUT" -C "$T" --sort=name --owner=0 --group=0 --numeric-owner qc18-final
(cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")") > qc18/final.sha256
echo "$n runs -> $OUT"; cat qc18/final.sha256
