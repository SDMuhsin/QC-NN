#!/usr/bin/env bash
# s2 in the full chimera SoC (Questa, remote tau host): nn/sim/run_rtl.sh with
#   mode qc (default): the QC-GeMMX cluster of qcacc/hw/gen.sh (build/qcacc/generated), the qcacc compiler
#     in qc mode (one call per conv + requant table; -g: 42 per-group calls), the QC tree's GeMMX
#     headers and -DNN_QC_RQ; remote work dir /tmp/ckp908/qcacc_kul
#   mode gemmx (-m gemmx, control): s2 as int8 ternary weights on the UNMODIFIED base cluster
#     (hw/kulcluster/generated, read-only; 42 per-group calls); remote work dir /tmp/ckp908/qcacc_ctl
# The remote design is compiled on the first run in that dir (rm -rf <dir>/work to force).
# Local results: build/qcacc/rtl/<tag>/ (+ qc_summary.txt, qcacc/hw/sim/summary.py).
#   qcacc/hw/sim/run_rtl_qc.sh [-m qc|gemmx] [-g] [-S step] [run_rtl.sh options: -H -n -f -t -l -c] [-- build flags]
#   -S step: stop after that step (e.g. conv1) -> -DNN_STOP_AFTER=<index> -DNN_FULL_CHECK
#   default tag: <mode>[_pg]_stop_<step> with -S, else <mode>[_pg]_img<first>_n<images>
#   e.g. qcacc/hw/sim/run_rtl_qc.sh -H usask -n 10 -f 0
#        qcacc/hw/sim/run_rtl_qc.sh -m gemmx -H tau5 -n 3
set -euo pipefail
QHW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QCNN=$(cd "$QHW/../.." && pwd)
S2=${QC_S2:-/tmp/${USER:-$(id -un)}/qc/final/int8/s2.pt}
MODE=qc; PG=""; STOP=""; TAG=""; N=1; F=0; ARGS=()
while [ $# -gt 0 ] && [ "$1" != -- ]; do
  case $1 in -m) MODE=$2; shift 2;; -g) PG=1; shift;; -S) STOP=$2; shift 2;; -t) TAG=$2; shift 2;;
             -n) N=$2; ARGS+=(-n "$2"); shift 2;; -f) F=$2; ARGS+=(-f "$2"); shift 2;;
             *) ARGS+=("$1"); shift;; esac
done
[ "${1:-}" = -- ] && shift
FLAGS=("$@")
[ "$MODE" = gemmx ] && PG=1
PGF=${PG:+ --per-group}
[ -n "$STOP" ] && DEF=${MODE}${PG:+_pg}_stop_$STOP || DEF=${MODE}${PG:+_pg}_img${F}_n${N}
TAG=${TAG:-$DEF}
if [ -n "$STOP" ]; then
  IDX=$(cd "$QCNN" && python3 -c "
import torch
from qcacc.compile.lower import QCProgram
st = QCProgram(torch.load('$S2', weights_only=False), '$MODE', $([ -n "$PG" ] && echo True || echo None)).steps
print([s.name for s in st].index('$STOP'))" 2>/dev/null | tail -1)
  FLAGS+=(-DNN_FULL_CHECK -DNN_STOP_AFTER=$IDX)
fi
export NN_RTL_OUT=$QCNN/build/qcacc/rtl; mkdir -p "$NN_RTL_OUT"
export KUL_WS=${KUL_WS:-$QCNN/build/kulcluster/chimera_ws}     # the (initialised) chimera copy of hw/kulcluster
if [ "$MODE" = qc ]; then
  [ -f "$QCNN/build/qcacc/generated/kulcluster_sim.sv" ] || { echo "run qcacc/hw/gen.sh first"; exit 1; }
  export KUL_BUILD=$QCNN/build/qcacc KUL_GEN=$QCNN/build/qcacc/generated
  export KUL_VSIM_DIR=${KUL_VSIM_DIR:-/tmp/ckp908/qcacc_kul}
  FLAGS+=(-DNN_QC_RQ)
else
  # base cluster RTL + headers, read-only: a private build dir whose snax tree is the base one
  export KUL_BUILD=$QCNN/build/qcacc/ctl KUL_GEN=$QCNN/hw/kulcluster/generated
  mkdir -p "$KUL_BUILD"; ln -sfn "$QCNN/build/kulcluster/snax_cluster" "$KUL_BUILD/snax_cluster"
  export KUL_VSIM_DIR=${KUL_VSIM_DIR:-/tmp/ckp908/qcacc_ctl}
fi
export NN_COMPILE="python3 -m qcacc.compile.main --mode $MODE$PGF --qparams $S2"
# run_rtl.sh's own nn/sim/summary.py cannot parse the qcacc compile log: its status is ignored, the QC
# summary below decides (exit 0 = bit-exact up to the stop step / all logits of a full run)
"$QCNN/nn/sim/run_rtl.sh" "${ARGS[@]}" -t "$TAG" -- "${FLAGS[@]}" > "$NN_RTL_OUT/$TAG.run_rtl.log" 2>&1 || true
grep '^\[run_rtl\]' "$NN_RTL_OUT/$TAG.run_rtl.log" || true
(cd "$QCNN" && python3 -m qcacc.hw.sim.summary "$NN_RTL_OUT/$TAG" --qparams "$S2" --mode "$MODE"${PG:+ --per-group}) \
  | tee "$NN_RTL_OUT/$TAG/qc_summary.txt"
exit "${PIPESTATUS[0]}"
