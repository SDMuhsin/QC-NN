#!/usr/bin/env bash
# v3 local (iverilog) unit tests:  qc18acc/hw3/sim/run_unit.sh [mini]
#   tb_pe   v3 qa_pe (2 blocks per step) vs a behavioural model
#   mini    (optional, ~3 min) full v3 TB on the random mini program (hw3/tb/mini.py), 1 image, maps + logits
set -eu
H=$(cd "$(dirname "$0")/.." && pwd); REPO=$(cd "$H/../.." && pwd)
W=${QC_LOCAL:-/tmp/root/qc18acc3}/unit; mkdir -p "$W"
RTL=$(grep -v '^//' "$H/rtl/qc18acc.f" | sed "s|^|$H/rtl/|")
iv() { iverilog -g2012 "$@" 2>&1 | grep -v "sorry: constant selects\|warning\|^ *: " || true; }
iv -o "$W/pe" -s tb_pe "$H/rtl/qa_pkg.sv" "$H/rtl/qa_pe.sv" "$H/tb/tb_pe.sv" && vvp "$W/pe" | tail -1
if [ "${1:-}" = mini ]; then
    (cd "$REPO" && python3 -m qc18acc.hw3.tb.mini "$W/mini" --images 1)
    awk '$1 == "pass" { print $3 }' "$W/mini/program.txt" > "$W/mini/names.txt"
    iv -o "$W/tb" -s qa_tb $RTL "$H/tb/qa_tb.sv" && vvp "$W/tb" +DIR="$W/mini" +NIMG=1 | grep -E "IMAGE|RESULT|MISMATCH"
fi
