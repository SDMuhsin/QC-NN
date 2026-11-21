#!/usr/bin/env bash
# R37: impl/r37/pt37.tcl (impl/r21/pt_hub.tcl + latency / feed-through hook) on hub run <tag> at <corner>; env as impl/r31/pt31.sh.
#   qc18bacc/impl/r37/pt37.sh <tag> <corner>    (QB_PT_PERIOD, QB_IO_LAT, QB37_LAT p50, QB37_FT 1)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD; tag=${1:?tag}; c=${2:?corner}; d=$B/pnr/$tag
export QB_SYN=${QB_SYN:-r26_ptr} QB9_W=${QB9_W:-$B/r26_w} QB_IO_LAT=${QB_IO_LAT:-$(cat "$d/r34_L.txt")}
( . "$root/flow/tsmc65/common/tool.sh"; . "$d/kit.env"; set -a; . "$B/syn/$QB_SYN/run.env"; set +a
  mkdir -p "$d/w_r37_$c" "$d/rpt"; cd "$d/w_r37_$c" || exit 1
  QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c QB21_SDC=${R31_SDC:-$QB9_W/cfg_$tag/qb_hub.sdc} QB_PT_PERIOD=${QB_PT_PERIOD:?QB_PT_PERIOD} \
  R31_PTHUB=$root/qc18bacc/impl/r21/pt_hub.tcl qc_tool "$d/r37_pt_$c.log" pt_shell -f "$here/pt37.tcl" )
rm -rf "$d/w_r37_$c"
grep -h "^R37" "$d/r37_pt_$c.log"; cat "$d/pt_hub_$c.txt"; echo "R37_PT_ERRORS $c $(grep -c '^Error' "$d/r37_pt_$c.log")"
