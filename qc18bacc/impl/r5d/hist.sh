#!/usr/bin/env bash
# R5d step 1: violating-endpoint dump of a routed qb_col_blk run (impl/r5d/hist.tcl), env as impl/r5a/post.sh pt.
#   qc18bacc/impl/r5d/hist.sh <tag> <corner> <period>   -> $QC_BUILD/r5d/hist_<tag>/viol_<corner>_p<period>.txt
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
tag=$1; c=$2; per=$3
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; dir=$QC_BUILD/pnr/$tag
. "$root/flow/tsmc65/common/tool.sh"
export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
. "$dir/kit.env"
w=$QC_BUILD/r5d/hist_$tag/${c}_p$per; mkdir -p "$w"; ln -sfn "$dir/out" "$w/out"
( set -a; . "$(dirname "$NETLIST")/run.env"; set +a
  export QC_SDC=$root/qc18bacc/impl/constraints.sdc QC_PT_HOOK= QC_PERIOD=$per QB5D_R5A=$root/qc18bacc/impl/r5a
  cd "$w" && QC_PNR_OUT=$w QC_TOP=$TOP QC_CORNER=$c qc_tool hist.log pt_shell -f "$here/hist.tcl" )
cp "$w/viol_$c.txt" "$QC_BUILD/r5d/hist_$tag/viol_${c}_p$per.txt"; cp "$w/pt_blk_$c.txt" "$QC_BUILD/r5d/hist_$tag/pt_${c}_p$per.txt"
grep -E "QB5D_HIST|^Error" "$w/hist.log" | head
