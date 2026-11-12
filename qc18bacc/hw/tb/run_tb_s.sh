#!/usr/bin/env bash
# Bit-exact self-check of a qb_lane_s variant against gen_s.py (Verilator 5.050 --binary):
#   qc18bacc/hw/tb/run_tb_s.sh <top> <XW> <MW> <TW> <SHW> <SB> rand|real [gen_s.py args...]
#   (qbs_base tops: pass --base)
# Build / vectors in QB_TB_WORK (default /tmp/$USER/qc18bacc/tb)/<top>_<kind>.  Prints the bench's QB_TB line.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); RTL=$HERE/../rtl
VL=${VERILATOR:-/workspace/eda/opt/verilator/bin/verilator}
WORK=${QB_TB_WORK:-/tmp/${USER:-$(id -un)}/qc18bacc/tb}
top=$1 xw=$2 mw=$3 tw=$4 shw=$5 sb=$6 kind=$7; shift 7
sw=$(( shw > 0 ? shw : 1 ))
d=$WORK/${top}_$kind; mkdir -p "$d"
python3 -I "$HERE/gen_s.py" "$kind" --xw "$xw" --mw "$mw" --tw "$tw" --shw "$shw" --sb "$sb" --out "$d/vec" "$@"
if [ ! -x "$d/obj/sim" ] || [ "$RTL/qb_lane_s.sv" -nt "$d/obj/sim" ] || [ "$HERE/tb_qb_lane_s.sv" -nt "$d/obj/sim" ]; then
    "$VL" --binary -j 8 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --Mdir "$d/obj" -o sim -DTOP="$top" -DXW="$xw" \
        -DMW="$mw" -DTW="$tw" -DSW="$sw" --top-module tb_qb_lane_s "$RTL/qb_lane_s.sv" "$HERE/tb_qb_lane_s.sv" \
        > "$d/build.log" 2>&1 || { tail -20 "$d/build.log"; exit 1; }
fi
"$d/obj/sim" +stim="$d/vec/stim.txt" +exp="$d/vec/exp.txt" | tee "$d/sim.log" | grep -E 'QB_TB|MISMATCH|Error|error'
