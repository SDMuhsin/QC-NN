#!/usr/bin/env bash
# Bit-exact self-check of qb_lane_f against gen_f.py (Verilator 5.050 --binary):
#   qc18bacc/hw/tb/run_tb_f.sh <MW> rand|real <tag> [gen_f.py args...]     (real: --params lanef_<run>.txt)
# Build / vectors in QB_TB_WORK (default /tmp/$USER/qc18bacc/tb)/qb_lane_f_<tag>; QBF_DEFS: extra Verilator defines
# (mutant tests).  Prints the bench's QB_TB line.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); RTL=$HERE/../rtl
VL=${VERILATOR:-/workspace/eda/opt/verilator/bin/verilator}
WORK=${QB_TB_WORK:-/tmp/${USER:-$(id -un)}/qc18bacc/tb}
mw=$1 kind=$2 tag=$3; shift 3
d=$WORK/qb_lane_f_$tag; mkdir -p "$d"
python3 -I "$HERE/gen_f.py" "$kind" --mw "$mw" --out "$d/vec" "$@"
"$VL" --binary -j 8 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --Mdir "$d/obj" -o sim -DQBF_MW="$mw" ${QBF_DEFS:-} \
    --top-module tb_qb_lane_f "$RTL/qb_lane_f.sv" "$HERE/tb_qb_lane_f.sv" > "$d/build.log" 2>&1 || { tail -20 "$d/build.log"; exit 1; }
"$d/obj/sim" +stim="$d/vec/stim.txt" +exp="$d/vec/exp.txt" | tee "$d/sim.log" | grep -E 'QB_TB|MISMATCH|Error|error'
