#!/usr/bin/env bash
# Standalone Verilog of the three ablation cores (qcacc/hw/chisel/ablation/AblGemm.scala):
#   qcacc/ablation/gen.sh   -> build/qcacc/ablation/rtl/AblGemm_{dense,ternary,qc}.sv
# Prereq: the overlaid snax_cluster tree of qcacc/hw/gen.sh (build/qcacc/snax_cluster).
set -euo pipefail
QA=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export QCNN=$(cd "$QA/../.." && pwd)
export KUL_BUILD=${QC_BUILD:-$QCNN/build/qcacc}
KUL_NO_VLT=1 source "$QCNN/hw/kulcluster/env.sh"
O=$KUL_BUILD/ablation/rtl; mkdir -p "$O"
S=$KUL_SNAX/hw/chisel_acc/src/main/scala/snax_acc
rm -rf "$S/qcgemm" "$S/ablation"
cp -r "$QCNN/qcacc/hw/chisel/qcgemm" "$S/qcgemm"
cp -r "$QCNN/qcacc/hw/chisel/ablation" "$S/ablation"
(cd "$KUL_SNAX/hw/chisel_acc" && sbt -batch "runMain snax_acc.ablation.AblGemmEmit dense $O" \
   "runMain snax_acc.ablation.AblGemmEmit ternary $O" "runMain snax_acc.ablation.AblGemmEmit qc $O") > "$O/sbt.log" 2>&1 \
  || { tail -30 "$O/sbt.log"; exit 1; }
for v in dense ternary qc; do
  [ -s "$O/AblGemm_$v.sv" ] || { echo "missing $O/AblGemm_$v.sv"; exit 1; }
  echo "$O/AblGemm_$v.sv: $(grep -c '^module' "$O/AblGemm_$v.sv") modules"
done
