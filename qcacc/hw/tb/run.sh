#!/usr/bin/env bash
# Unit test of the QC-GeMMX core (QcBlockGemm) against qcacc/model/array.py, Verilator.
#   qcacc/hw/tb/run.sh [stall_percent]     (default 30; prereq: qcacc/hw/gen.sh for the QC Chisel tree)
# 1. emits QcBlockGemm from the overlaid snax_cluster tree (sbt), 2. vectors (vectors.py: 200 random
# cases + all QC calls of s2 image 0), 3. Verilator build + run; then the same for the RescaleSIMD with
# the per-channel requant table (vectors_simd.py: 200 random cases, 1..8 groups, + the 9 one-call s2 convs).
# Exit 0 = both bit-exact.
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
rc=0
"$O/obj/Vtb" "$O/vectors.txt" "${1:-30}" | tee "$O/tb.log" || true
[ "${PIPESTATUS[0]}" = 0 ] || rc=1
# 2) RescaleSIMD + per-channel requant table (QcPipelinedRescaleSIMD) vs qcacc.model.requant
(cd "$KUL_SNAX/hw/chisel_acc" && sbt -batch "runMain snax_acc.qcgemm.QcPipelinedRescaleSIMDEmit $O/rtl_simd") > "$O/sbt_simd.log" 2>&1 \
  || { tail -20 "$O/sbt_simd.log"; exit 1; }
(cd "$QCNN" && "$PY" -m qcacc.hw.tb.vectors_simd "$O/vectors_simd.txt" --random 200 --real)
verilator --cc --exe --build -j 8 -O2 -Wno-fatal --top-module QcPipelinedRescaleSIMD -Mdir "$O/obj_simd" \
  "$O/rtl_simd/QcPipelinedRescaleSIMD.sv" "$QHW/tb/tb_qc_simd.cpp" -o Vtb_simd > "$O/verilator_simd.log" 2>&1 \
  || { tail -20 "$O/verilator_simd.log"; exit 1; }
# input-valid stalls only: the upstream PipelinedRescaleSIMD loses / repeats data under output_o
# back-pressure (lane valid shifts output_data_reg without a handshake), also with the table disabled
"$O/obj_simd/Vtb_simd" "$O/vectors_simd.txt" "${1:-30}" 1 | tee "$O/tb_simd.log" || true
[ "${PIPESTATUS[0]}" = 0 ] || rc=1
exit $rc
