#!/usr/bin/env bash
# Unit test of the QC-GeMMX core (QcBlockGemm) against qcacc/model/array.py, Verilator.
#   qcacc/hw/tb/run.sh [stall_percent]     (default 30; prereq: qcacc/hw/gen.sh for the QC Chisel tree)
# 1. emits QcBlockGemm from the overlaid snax_cluster tree (sbt), 2. vectors (vectors.py: 200 random
# cases + all 42 QC calls of s2 image 0), 3. Verilator build + run.  Exit 0 = bit-exact.
# Outputs in build/qcacc/tb/.
set -euo pipefail
QHW=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export QCNN=$(cd "$QHW/../.." && pwd)
export KUL_BUILD=${QC_BUILD:-$QCNN/build/qcacc}
PY=$(command -v python3)                                # torch / numpy (env.sh puts the snax venv first)
source "$QCNN/hw/kulcluster/env.sh"                     # sbt / JDK, Verilator
O=$KUL_BUILD/tb; mkdir -p "$O"
# keep the tree's Scala in sync with the repo (gen.sh does the same)
rm -rf "$KUL_SNAX/hw/chisel_acc/src/main/scala/snax_acc/qcgemm"
cp -r "$QHW/chisel/qcgemm" "$KUL_SNAX/hw/chisel_acc/src/main/scala/snax_acc/qcgemm"
(cd "$KUL_SNAX/hw/chisel_acc" && sbt -batch "runMain snax_acc.qcgemm.QcBlockGemmEmit $O/rtl") > "$O/sbt.log" 2>&1 \
  || { tail -20 "$O/sbt.log"; exit 1; }
(cd "$QCNN" && "$PY" -m qcacc.hw.tb.vectors "$O/vectors.txt" --random 200 --real)
verilator --cc --exe --build -j 8 -O2 -Wno-fatal --top-module QcBlockGemm -Mdir "$O/obj" \
  "$O/rtl/QcBlockGemm.sv" "$QHW/tb/tb_qc_blockgemm.cpp" -o Vtb > "$O/verilator.log" 2>&1 \
  || { tail -20 "$O/verilator.log"; exit 1; }
"$O/obj/Vtb" "$O/vectors.txt" "${1:-30}" | tee "$O/tb.log"
exit "${PIPESTATUS[0]}"
