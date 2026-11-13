#!/usr/bin/env bash
# Tile-level bit-exact bench of qb_core (Verilator 5.050 --binary) on vectors of export_core.py:
#   qc18bacc/hw/tb/run_tb_core.sh build            build the simulator in $QB_TB_WORK/qb_core (QBC_DEFS: extra defines)
#   qc18bacc/hw/tb/run_tb_core.sh run <imgdir>...  run it on each export directory (prints QB_CORE / QB_CORE_TB lines)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); RTL=$HERE/../rtl
VL=${VERILATOR:-/workspace/eda/opt/verilator/bin/verilator}
WORK=${QB_TB_WORK:-/tmp/${USER:-$(id -un)}/qc18bacc/tb}/qb_core${QBC_TAG:-}
case "$1" in
build) mkdir -p "$WORK"
       "$VL" --binary -j 16 -O2 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --Mdir "$WORK/obj" -o sim ${QBC_DEFS:-} \
           --top-module tb_qb_core "$RTL/qb_lane_f.sv" "$RTL/qb_dec.sv" "$RTL/qb_core.sv" "$HERE/tb_qb_core.sv" \
           > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; exit 1; }
       echo "QB_CORE_BUILD_OK $WORK" ;;
run)   shift; for d in "$@"; do "$WORK/obj/sim" +dir="$d" | tee "$d/sim${QBC_TAG:-}.log" | grep -E 'QB_CORE|MISMATCH|Error|error' ; done ;;
*)     sed -n '2,4p' "$0"; exit 1 ;;
esac
