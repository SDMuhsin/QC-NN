#!/usr/bin/env bash
# R45: after chain45b.sh: re-run the PT ETM-outlier diagnosis (fixed report_timing syntax).
set -u
R45=${R45:-$HOME/r45}; cd "$R45" || exit 1
while ! grep -q CHAIN45B_DONE chain45b.out 2>/dev/null; do sleep 20; done
cd pt && R45_PINS="act[2911] act[2910]" R45_SLEWS="0 0.0457 0.0942 0.2 0.3852" \
  "$R45/pt45.sh" /tmp/ckp908/qc18bacc/build/pnr/r35_colb tt "$R45/etmdiag45.tcl" "$R45/pt/etmdiag2_tt.log" 6.5
echo CHAIN45C_DONE
