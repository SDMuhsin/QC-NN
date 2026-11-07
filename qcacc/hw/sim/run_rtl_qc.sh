#!/usr/bin/env bash
# s2 on the QC-GeMMX cluster in the full chimera SoC (Questa, remote tau host): nn/sim/run_rtl.sh with
#   * the QC pickles of qcacc/hw/gen.sh (build/qcacc/generated) in their own remote work dir
#     (default /tmp/ckp908/qcacc_kul; compiled there on the first run, base dirs untouched),
#   * the qcacc compiler in qc mode (qcacc.compile.main --mode qc) and the QC tree's GeMMX headers,
#   * local results in build/qcacc/rtl/<tag>/ (+ qc_summary.txt, qcacc/hw/sim/summary.py).
#   default tag: stop_<step> with -S, else full
#   qcacc/hw/sim/run_rtl_qc.sh [-S step] [run_rtl.sh options] [-- build flags]
#   -S step: stop after that step (e.g. conv1_g1 -> -DNN_STOP_AFTER=<its index>, + -DNN_FULL_CHECK)
#   e.g. qcacc/hw/sim/run_rtl_qc.sh -S conv1_g1 -H usask      (conv0 + conv1, byte-exact check)
#        qcacc/hw/sim/run_rtl_qc.sh -H usask -n 1              (whole network, image 0)
set -euo pipefail
QHW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QCNN=$(cd "$QHW/../.." && pwd)
S2=${QC_S2:-/tmp/${USER:-$(id -un)}/qc/final/int8/s2.pt}
STOP=""; TAG=""; ARGS=()
while [ $# -gt 0 ] && [ "$1" != -- ]; do
  case $1 in -S) STOP=$2; shift 2;; -t) TAG=$2; shift 2;; *) ARGS+=("$1"); shift;; esac
done
TAG=${TAG:-${STOP:+stop_$STOP}}; TAG=${TAG:-full}
[ "${1:-}" = -- ] && shift
FLAGS=("$@")
if [ -n "$STOP" ]; then
  IDX=$(cd "$QCNN" && python3 -c "
import sys, torch
from qcacc.compile.lower import QCProgram
st = QCProgram(torch.load('$S2', weights_only=False), 'qc').steps
print([s.name for s in st].index('$STOP'))" 2>/dev/null | tail -1)
  FLAGS+=(-DNN_FULL_CHECK -DNN_STOP_AFTER=$IDX)
fi
[ -f "$QCNN/build/qcacc/generated/kulcluster_sim.sv" ] || { echo "run qcacc/hw/gen.sh first"; exit 1; }
export KUL_BUILD=$QCNN/build/qcacc                       # QC snax tree: GeMMX headers / runtime
export KUL_WS=${KUL_WS:-$QCNN/build/kulcluster/chimera_ws}   # the (initialised) chimera copy of hw/kulcluster
export KUL_GEN=$QCNN/build/qcacc/generated
export KUL_VSIM_DIR=${KUL_VSIM_DIR:-/tmp/ckp908/qcacc_kul}
export NN_RTL_OUT=$QCNN/build/qcacc/rtl
mkdir -p "$NN_RTL_OUT"
export NN_COMPILE="python3 -m qcacc.compile.main --mode qc --qparams $S2"
# run_rtl.sh's own nn/sim/summary.py cannot parse the qcacc compile log: its status is ignored, the QC
# summary below decides (exit 0 = bit-exact up to the stop step / logits of a full run)
"$QCNN/nn/sim/run_rtl.sh" "${ARGS[@]}" -t "$TAG" -- "${FLAGS[@]}" > "$NN_RTL_OUT/$TAG.run_rtl.log" 2>&1 || true
grep '^\[run_rtl\]' "$NN_RTL_OUT/$TAG.run_rtl.log" || true
(cd "$QCNN" && python3 -m qcacc.hw.sim.summary "$NN_RTL_OUT/$TAG" --qparams "$S2") | tee "$NN_RTL_OUT/$TAG/qc_summary.txt"
exit "${PIPESTATUS[0]}"
