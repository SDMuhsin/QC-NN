#!/usr/bin/env bash
# Bit-exact self-check of the qc18bacc microblocks against gen.py (Verilator 5.050 --binary):
#   qc18bacc/hw/tb/run_tb.sh pe <KB> <ACC_W> [N] [seed]      qb_pe
#   qc18bacc/hw/tb/run_tb.sh lane_n|lane_w [N] [seed]         qb_lane_n / qb_lane_w
# Build / vectors in QB_TB_WORK (default /tmp/$USER/qc18bacc/tb).  Prints the bench's "QB_TB ... PASS|FAIL" line.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); RTL=$HERE/../rtl
VL=${VERILATOR:-/workspace/eda/opt/verilator/bin/verilator}
WORK=${QB_TB_WORK:-/tmp/${USER:-$(id -un)}/qc18bacc/tb}
dut=$1; shift
case "$dut" in
pe)     kb=$1 aw=$2 n=${3:-200000} seed=${4:-1}; tag=pe_k${kb}_a${aw}
        args=(-GKB="$kb" -GACC_W="$aw" --top-module tb_qb_pe "$RTL/qb_pe.sv" "$HERE/tb_qb_pe.sv")
        gargs=(pe --kb "$kb" --accw "$aw") ;;
lane_n|lane_w) n=${1:-200000} seed=${2:-1}; tag=$dut
        args=(--top-module tb_qb_lane "$RTL/qb_lane.sv" "$HERE/tb_qb_lane.sv")
        [ "$dut" = lane_w ] && args+=(-DLANE_W)
        gargs=("$dut") ;;
*)      sed -n '2,5p' "$0"; exit 1 ;;
esac
d=$WORK/$tag; mkdir -p "$d"
python3 -I "$HERE/gen.py" "${gargs[@]}" --n "$n" --seed "$seed" --out "$d/vec"
"$VL" --binary -j 8 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --Mdir "$d/obj" -o sim "${args[@]}" > "$d/build.log" 2>&1 ||
    { tail -20 "$d/build.log"; exit 1; }
"$d/obj/sim" +stim="$d/vec/stim.txt" +exp="$d/vec/exp.txt" | tee "$d/sim.log" | grep -E 'QB_TB|MISMATCH|Error|error'
