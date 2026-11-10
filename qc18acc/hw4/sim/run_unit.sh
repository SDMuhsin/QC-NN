#!/usr/bin/env bash
# v4 local (iverilog) tests:  qc18acc/hw4/sim/run_unit.sh [mini]
#   compile  full v4 RTL + TB (elaboration check)
#   mini     (optional) full v4 TB on the random mini program (hw4/tb/mini.py), 1 image, maps + logits
# (tb_pe: the PE is v3's unchanged, hw3/sim/run_unit.sh)
set -eu
H=$(cd "$(dirname "$0")/.." && pwd); REPO=$(cd "$H/../.." && pwd)
W=${QC_LOCAL:-/tmp/root/qc18acc4}/unit; mkdir -p "$W"
RTL=$(grep -v '^//' "$H/rtl/qc18acc.f" | sed "s|^|$H/rtl/|")
iv() { iverilog -g2012 "$@" 2>&1 | grep -v "sorry: constant selects\|warning\|^ *: " || true; }
iv -o "$W/tb" -s qa_tb $RTL "$H/tb/qa_tb.sv"
if [ "${1:-}" = mini ]; then
    (cd "$REPO" && python3 -m qc18acc.hw4.tb.mini "$W/mini" --images 1)
    awk '$1 == "pass" { print $3 }' "$W/mini/program.txt" > "$W/mini/names.txt"
    vvp "$W/tb" +DIR="$W/mini" +NIMG=1 | grep -E "TB|IMAGE|RESULT|MISMATCH|PASSCYC|PERF|rror" | head -60
fi
