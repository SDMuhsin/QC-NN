#!/usr/bin/env bash
# Image-level bench of qb_act2 (R2b; Verilator 5.050 --binary) on vectors of export_act2.py:
#   qc18bacc/hw/tb/run_tb_act2.sh build            build in $QB_TB_WORK/qb_act2$QBA_TAG (QBA_DEFS: extra defines, mutants)
#   qc18bacc/hw/tb/run_tb_act2.sh run <imgdir>...  run on each export directory (prints QB_ACT2 / QB_ACT2_TB lines)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); RTL=$HERE/../rtl
VL=${VERILATOR:-/workspace/eda/opt/verilator/bin/verilator}
WORK=${QB_TB_WORK:-/tmp/${USER:-$(id -un)}/qc18bacc/tb}/qb_act2${QBA_TAG:-}
case "$1" in
build) mkdir -p "$WORK"
       "$VL" --binary -j 16 -O2 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --Mdir "$WORK/obj" -o sim ${QBA_DEFS:-} \
           --top-module tb_qb_act2 "$RTL/qb_act_net.sv" "$RTL/qb_act.sv" "$RTL/qb_act2_net.sv" "$RTL/qb_act2.sv" \
           "$HERE/tb_qb_act2.sv" > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; exit 1; }
       echo "QB_ACT2_BUILD_OK $WORK" ;;
run)   shift; for d in "$@"; do "$WORK/obj/sim" +dir="$d" | tee "$d/sim_act2${QBA_TAG:-}.log" | grep -E 'QB_ACT2|MISMATCH|Error|error' ; done ;;
*)     sed -n '2,4p' "$0"; exit 1 ;;
esac
