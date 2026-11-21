#!/usr/bin/env bash
# R45: the remaining probes, one tool job at a time (tau6): waits for act45.sh, then
#   1. PrimeTime column tt ETM-outlier diagnosis (etmdiag45.tcl)   2. OR ICG enable nets, hub r35_hubC place / cts
#   3. minimal repro v1b: router LEF with only 'MINIMUMCUT 2 WIDTH 0.300' kept on M1 (DRT-0073 or not)
set -u
R45=${R45:-$HOME/r45}; cd "$R45" || exit 1
while ! grep -q ACT45_DONE act45.out 2>/dev/null; do sleep 30; done
mkdir -p pt && cd pt
R45_PINS="act[2911] act[2910] pf[507]" R45_SLEWS="0 0.0457 0.0942 0.2 0.3852" \
  "$R45/pt45.sh" /tmp/ckp908/qc18bacc/build/pnr/r35_colb tt "$R45/etmdiag45.tcl" "$R45/pt/etmdiag_tt.log" 6.5
cd "$R45"
for s in place cts; do
  R45_STEP=$s QC_BUILD=$R45/build bash /tmp/ckp908/qc18bacc/r35_snap/qc18bacc/impl/r29/or29.sh hubC "$R45/icgdrv45.tcl" icg_$s.log
  grep "R45_" "$R45/build/pnr/hubC/icg_$s.log"
done
R45_LEF=$R45/lef_mc1.lef ./run45.sh v1b $R45/lef_mc1.lef none > v1b.out 2>&1; grep "DRT-0073 count\|PNR_DONE" v1b.out
echo CHAIN45_DONE
