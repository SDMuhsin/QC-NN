#!/usr/bin/env bash
# R31: impl/r31/pt31.tcl on run <tag> at <corner> (env as impl/r21/run.sh post).  On tau from the snapshot root:
#   qc18bacc/impl/r31/pt31.sh <tag> <corner>    (QB_PT_PERIOD = the run's period)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD; tag=${1:?tag}; c=${2:?corner}; d=$B/pnr/$tag
export QB_SYN=${QB_SYN:-r26_ptr} QB9_W=${QB9_W:-$B/r26_w} QB_IO_LAT=${QB_IO_LAT:-1.30}
( . "$root/flow/tsmc65/common/tool.sh"; . "$d/kit.env"; set -a; . "$B/syn/$QB_SYN/run.env"; set +a
  mkdir -p "$d/w_r31_$c" "$d/rpt"; cd "$d/w_r31_$c" || exit 1
  QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c QB21_SDC=${R31_SDC:-$QB9_W/cfg_$tag/qb_hub.sdc} QB_PT_PERIOD=${QB_PT_PERIOD:?QB_PT_PERIOD} \
  R31_PTHUB=$root/qc18bacc/impl/r21/pt_hub.tcl qc_tool "$d/r31_${R31_PTT:-pt31}_$c.log" pt_shell -f "$here/${R31_PTT:-pt31}.tcl" )
rm -rf "$d/w_r31_$c"
grep -h "^R31PT\|^R31CLK\|^R31HOLD" "$d/r31_${R31_PTT:-pt31}_$c.log" | cut -c1-400; echo "R31_PT_ERRORS $c $(grep -c '^Error' "$d/r31_${R31_PTT:-pt31}_$c.log") PARA044 $(grep -c "PARA-044)" "$d/r31_${R31_PTT:-pt31}_$c.log")"
