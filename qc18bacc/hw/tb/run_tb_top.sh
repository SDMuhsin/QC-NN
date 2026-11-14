#!/usr/bin/env bash
# Full-image bench of qb_top (R3a; Verilator 5.050 --binary) on vectors of export_top.py:
#   qc18bacc/hw/tb/run_tb_top.sh build            build in $QB_TB_WORK/qb_top$QBT_TAG (QBT_DEFS: extra defines, mutants)
#   qc18bacc/hw/tb/run_tb_top.sh run <imgdir>...  run on each export directory (prints QB_TOP lines)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); RTL=$HERE/../rtl
VL=${VERILATOR:-/workspace/eda/opt/verilator/bin/verilator}
WORK=${QB_TB_WORK:-/tmp/${USER:-$(id -un)}/qc18bacc/tb}/qb_top${QBT_TAG:-}
case "$1" in
build) mkdir -p "$WORK"
       "$VL" --binary -j 16 -O2 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --Mdir "$WORK/obj" -o sim ${QBT_DEFS:-} \
           --top-module tb_qb_top "$RTL/qb_lane_f.sv" "$RTL/qb_dec.sv" "$RTL/qb_core.sv" "$RTL/qb_act_net.sv" \
           "$RTL/qb_act.sv" "$RTL/qb_act2_net.sv" "$RTL/qb_act2.sv" "$RTL/qb_top.sv" "$HERE/tb_qb_top.sv" \
           > "$WORK/build.log" 2>&1 || { grep -E "%Error" "$WORK/build.log" | head -30; exit 1; }
       echo "QB_TOP_BUILD_OK $WORK" ;;
run)   shift; for d in "$@"; do "$WORK/obj/sim" +dir="$d" | tee "$d/sim_top${QBT_TAG:-}.log" | grep -E 'QB_TOP|MISMATCH|Error|error|fatal' | head -60; done ;;
*)     sed -n '2,4p' "$0"; exit 1 ;;
esac
