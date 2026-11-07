#!/usr/bin/env bash
# qcacc/sw/build.sh gemmx|qc|dense [flags]: chimera ELF (nn/sw/build.sh, tools/llvm17) of qcacc/build/MODE/gen
#   -> qcacc/build/MODE/sw/resnet8.memisl.elf (dense: nn/build/gen -> nn/build/sw); prints the weight blob bytes.
#   qc: for the QC cluster (build/qcacc/snax_cluster headers, -DNN_QC_RQ); gemmx / dense: the base cluster.
set -euo pipefail
Q=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODE=${1:?mode gemmx|qc|dense}; shift
if [ "$MODE" = dense ]; then O=$Q/../nn/build/sw; else O=$Q/build/$MODE/sw; export NN_GEN=$Q/build/$MODE/gen NN_BUILD=$O; fi
QC=()
if [ "$MODE" = qc ]; then   # QC cluster: its GeMMX headers / lib (qcacc/hw/gen.sh) + the requant-table hook
  export KUL_BUILD=${QC_BUILD:-$Q/../build/qcacc}; QC=(-DNN_QC_RQ)
fi
mkdir -p "$Q/build"; L=$Q/build/elf_$MODE.log
"$Q/../nn/sw/build.sh" "${QC[@]}" "$@" > "$L" 2>&1 || { tail -20 "$L"; exit 1; }
"$Q/../tools/llvm17/bin/llvm-nm" -S --size-sort "$O/resnet8.memisl.elf" | awk -v m="$MODE" '
  $4 ~ /^blob_w_conv/ {w += strtonum("0x" $2)} $4 ~ /^blob_/ {b += strtonum("0x" $2)}
  END {printf "%s ELF: conv blobs %d B, all blobs %d B\n", m, w, b}'
"$Q/../tools/llvm17/bin/llvm-size" "$O/resnet8.memisl.elf"
