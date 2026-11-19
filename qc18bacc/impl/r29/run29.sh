#!/usr/bin/env bash
# R29 (results/r29.md): antenna fix before DR on a copy of a routed-stage run (opt-in; defaults of other flows unchanged).
# On tau from the snapshot root:
#   qc18bacc/impl/r29/run29.sh mk <src> <tag>   new run <tag>: copies <src>'s config / kit / rc / grt db (+ <src>
#                                                rpt/antenna.rpt pins -> r29_seed.txt), no DR data
#   qc18bacc/impl/r29/run29.sh dio <tag>        dio29.tcl (R29_* knobs; R29_SEED defaults to r29_seed.txt)
#   qc18bacc/impl/r29/run29.sh dr|post|ant|abs|fin <tag>   impl/r28/run28.sh (r26_p1 / r28 settings, QB9_PER 3.40)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
export QB15_GADJ_L=${QB15_GADJ_L-"M5-M9 0.10"}
step=${1:?step}
case $step in
mk) s=$B/pnr/${2:?src}; d=$B/pnr/${3:?tag}; mkdir -p "$d/db" "$d/rpt" "$d/out"
    for f in config.tcl kit.env mplace.tcl macros.txt pins9_data.tcl summary.txt; do cp "$s/$f" "$d/"; done
    cp -r "$s/rc" "$d/"; cp "$s/db/grt.odb" "$d/db/grt_r29in.odb"; cp "$s/db/grt.sdc" "$d/db/grt_r29in.sdc"
    cp "$d/db/grt_r29in.odb" "$d/db/grt.odb"; cp "$d/db/grt_r29in.sdc" "$d/db/grt.sdc"
    [ -s "$s/rpt/antenna.rpt" ] && sed -n 's/^ *Pin: \([^ ]*\) .*/\1/p' "$s/rpt/antenna.rpt" | sort -u > "$d/r29_seed.txt"
    echo "R29_MK $3 from $2 seed $(wc -l < "$d/r29_seed.txt" 2>/dev/null)" ;;
dio) d=$B/pnr/${2:?tag}; export R29_SEED=${R29_SEED-$d/r29_seed.txt}
     "$here/or29.sh" "$2" "$here/dio29.tcl" r29_dio.log; grep -h "R29_DIO" "$d/r29_dio.log" ;;
dr|post|ant|abs|fin) "$root/qc18bacc/impl/r28/run28.sh" "$step" "${2:?tag}" ;;
*) sed -n '2,9p' "$0"; exit 1 ;;
esac
