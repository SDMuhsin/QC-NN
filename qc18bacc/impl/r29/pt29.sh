#!/usr/bin/env bash
# R29: impl/r29/pt29.tcl on run <tag> at corner tt (env as impl/r21/run.sh post).  On tau from the snapshot root:
#   qc18bacc/impl/r29/pt29.sh <tag>
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD; tag=${1:?tag}; d=$B/pnr/$tag
export QB_SYN=${QB_SYN:-r26_ptr} QB9_W=${QB9_W:-$B/r26_w} QB_IO_LAT=${QB_IO_LAT:-1.30}
( . "$root/flow/tsmc65/common/tool.sh"; . "$d/kit.env"; set -a; . "$B/syn/$QB_SYN/run.env"; set +a
  mkdir -p "$d/w_r29pt"; cd "$d/w_r29pt" || exit 1
  QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=tt QB21_SDC=$QB9_W/cfg_$tag/qb_hub.sdc QB_PT_PERIOD=${QB_PT_PERIOD:-3.40} \
  R29_PTHUB=$root/qc18bacc/impl/r21/pt_hub.tcl qc_tool "$d/r29_pt.log" pt_shell -f "$here/${R29_PTT:-pt29.tcl}" )
grep -h "R29PT\|R29PTC" "$d/r29_pt.log" | cut -c1-300
