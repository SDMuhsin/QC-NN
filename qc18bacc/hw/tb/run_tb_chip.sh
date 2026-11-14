#!/usr/bin/env bash
# Image-to-logits streaming bench of qb_chip (R3c; Verilator 5.050 --binary) on vectors of export_top3.py:
#   qc18bacc/hw/tb/run_tb_chip.sh build                       build in $QB_TB_WORK/qb_chip$QBT_TAG (QBT_DEFS: mutants)
#   qc18bacc/hw/tb/run_tb_chip.sh run <prog dir> <imgdir>...  stream the images back to back (one program load)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); RTL=$HERE/../rtl
VL=${VERILATOR:-/workspace/eda/opt/verilator/bin/verilator}
WORK=${QB_TB_WORK:-/tmp/${USER:-$(id -un)}/qc18bacc/tb}/qb_chip${QBT_TAG:-}
case "$1" in
build) mkdir -p "$WORK"
       "$VL" --binary -j 16 -O2 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --Mdir "$WORK/obj" -o sim ${QBT_DEFS:-} \
           --top-module tb_qb_chip "$RTL/qb_lane_f.sv" "$RTL/qb_dec.sv" "$RTL/qb_core.sv" "$RTL/qb_act_net.sv" \
           "$RTL/qb_act.sv" "$RTL/qb_act2_net.sv" "$RTL/qb_act2.sv" "$RTL/qb_seq.sv" "$RTL/qb_top.sv" "$RTL/qb_head.sv" \
           "$RTL/qb_chip.sv" "$HERE/tb_qb_chip.sv" > "$WORK/build.log" 2>&1 || { grep -E "%Error" "$WORK/build.log" | head -30; exit 1; }
       echo "QB_CHIP_BUILD_OK $WORK" ;;
run)   shift; P=$1; shift; i=0; A=()
       for d in "$@"; do A+=("+dir$i=$d"); i=$((i + 1)); done
       "$WORK/obj/sim" +prog="$P" +n=$i ${QBT_TAG:+"+tag=$QBT_TAG"} "${A[@]}" | tee "$P/../sim_chip${QBT_TAG:-}.log" | grep -E 'QB_CHIP|MISMATCH|Error|error|fatal' | head -60 ;;
*)     sed -n '2,4p' "$0"; exit 1 ;;
esac
