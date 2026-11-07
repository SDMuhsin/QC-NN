#!/usr/bin/env bash
# qcacc/sw/native.sh gemmx|qc [-DNN_FULL_CHECK]: nn/sw on x86 (nn/sw/native/run.sh) with the tables of
# qcacc/build/MODE/gen (python3 -m qcacc.compile.main --mode MODE); qc mode on the C QC-GeMMX model with the
# requant table (-DNN_QC_RQ, QC tree headers; works for both the 9-call and the --per-group 42-call build).
# Exit 0 = every step checksum and every logit bit-exact.
set -euo pipefail
Q=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODE=${1:?mode gemmx|qc}; shift
QC=()
if [ "$MODE" = qc ]; then   # QC tree headers (requant-table CSRs, qcacc/hw/gen.sh) + table programming in nn_cluster.c
  export NN_NATIVE_C=$Q/sw/native_qc.c KUL_SNAX=${QC_SNAX:-$Q/../build/qcacc/snax_cluster}
  QC=(-DNN_QC_RQ)
fi
NN_GEN=$Q/build/$MODE/gen NN_NATIVE_BUILD=$Q/build/$MODE/native exec "$Q/../nn/sw/native/run.sh" "${QC[@]}" "$@"
