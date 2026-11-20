#!/usr/bin/env bash
# R31: the R22 budget gate of run <tag> re-measured at the corrected GRT capacity (impl/r31/cuts31.py, R31_BADJ
# [= QB15 run adjustment "M2-M3 0.6 M4 0.25 M5-M9 0.10"]) on the gate GRT grt_pl -> <run>/bud_pl31/, gate22.py.
# R31_RADJ: the run adjustment for the GRT-resource calibration (default R31_BADJ); R31_GSFX: output dir suffix
#   qc18bacc/impl/r31/gate31.sh <tag>      (after impl/r22/run.sh gate; reuses bud_pl dumps)
set -u
here=$(cd "$(dirname "$0")" && pwd); I=$(cd "$here/.." && pwd)
B=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; tag=${1:?tag}; d=$B/pnr/$tag; o=$d/bud_pl31${R31_GSFX:-}; g=$d/grt_pl
export R31_BADJ=${R31_BADJ:-"M2-M3 0.6 M4 0.25 M5-M9 0.10"}
mkdir -p "$o"; cp "$d/bud_pl/obs.txt" "$d/bud_pl/q1.log" "$o/"
export QB21_SROWS="$(sed -n 's/^set ::QB15_BANDS {\(.*\)}/\1/p' "$d/mplace.tcl" | tr ' ' '\n' | paste - - - | awk '$1 ~ /^S[0-3]$/ {printf "%s ", $2}')"
python3 -I "$here/cuts31.py" "$g/route.guide" "$g/netcls2.txt" "$o/obs.txt" "$g/grt.log" "$d/mplace.tcl" "$o" "${R31_RADJ:-$R31_BADJ}" 0.25 > "$o/cuts31.log" 2>&1
echo R31_CUTS rc $?
python3 -I "$I/r22/gate22.py" "$o" "$d" > "$o/gate31.txt"; grep -h "WORST\|GATE" "$o/gate31.txt" | head -4 | cut -c1-200
