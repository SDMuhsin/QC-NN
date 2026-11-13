#!/usr/bin/env bash
# Pass-level bit-exact bench of qb_act (Verilator 5.050 --binary) on vectors of export_act.py:
#   qc18bacc/hw/tb/run_tb_act.sh build            build in $QB_TB_WORK/qb_act$QBA_TAG (QBA_DEFS: extra defines, mutants)
#   qc18bacc/hw/tb/run_tb_act.sh run <imgdir>...  run on each export directory (prints QB_ACT / QB_ACT_TB lines)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); RTL=$HERE/../rtl
VL=${VERILATOR:-/workspace/eda/opt/verilator/bin/verilator}
WORK=${QB_TB_WORK:-/tmp/${USER:-$(id -un)}/qc18bacc/tb}/qb_act${QBA_TAG:-}
case "$1" in
build) mkdir -p "$WORK"
       "$VL" --binary -j 16 -O2 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --Mdir "$WORK/obj" -o sim ${QBA_DEFS:-} \
           --top-module tb_qb_act "$RTL/qb_act_net.sv" "$RTL/qb_act.sv" "$HERE/tb_qb_act.sv" \
           > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; exit 1; }
       echo "QB_ACT_BUILD_OK $WORK" ;;
run)   shift; for d in "$@"; do "$WORK/obj/sim" +dir="$d" | tee "$d/sim_act${QBA_TAG:-}.log" | grep -E 'QB_ACT|MISMATCH|Error|error' ; done ;;
*)     sed -n '2,4p' "$0"; exit 1 ;;
esac
