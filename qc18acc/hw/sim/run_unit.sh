#!/usr/bin/env bash
# Local (iverilog) unit tests:  qc18acc/hw/sim/run_unit.sh [mini]
#   tb_pe   qa_pe vs a behavioural block-PE model (random codes / activations / tile lengths, capture, shift)
#   tb_ppu  qa_ppu_lane vs golden-arithmetic vectors (ppu_vectors.py: RELU, RAW16, RES_ID, RES_R, ties, negatives)
#   mini    (optional, ~3 min) full TB on the random mini program (mini.py), 1 image, maps + logits
set -eu
H=$(cd "$(dirname "$0")/.." && pwd); REPO=$(cd "$H/../.." && pwd)
W=${QC_LOCAL:-/tmp/root/qc18acc}/unit; mkdir -p "$W"
RTL=$(sed -n 's|^\([a-z].*\.sv\)$|'"$H"'/rtl/\1|p' "$H/rtl/qc18acc.f")
iv() { iverilog -g2012 "$@" 2>&1 | grep -v "sorry: constant selects\|warning\|^ *: " || true; }
iv -o "$W/pe" -s tb_pe "$H/rtl/qa_pkg.sv" "$H/rtl/qa_pe.sv" "$H/tb/tb_pe.sv" && vvp "$W/pe" | tail -1
(cd "$REPO" && python3 -m qc18acc.hw.tb.ppu_vectors "$W/ppu.hex" > /dev/null)
iv -o "$W/ppu" -s tb_ppu "$H/rtl/qa_pkg.sv" "$H/rtl/qa_ppu_lane.sv" "$H/tb/tb_ppu.sv" && vvp "$W/ppu" +VEC="$W/ppu.hex" | tail -1
if [ "${1:-}" = mini ]; then
    (cd "$REPO" && python3 -m qc18acc.hw.tb.mini "$W/mini" --images 1)
    awk '$1 == "pass" { print $3 }' "$W/mini/program.txt" > "$W/mini/names.txt"
    iv -o "$W/tb" -s qa_tb $RTL "$H/tb/qa_tb.sv" && vvp "$W/tb" +DIR="$W/mini" +NIMG=1 | grep -E "IMAGE|RESULT|MISMATCH"
fi
