#!/usr/bin/env bash
# Sign-off of a routed hardened-PE column (results/pnr_pe.md), on the build host from the repository root:
#   QB_HB_ETM_DIR=<pe run>/out/etm qc18bacc/impl/hard/col_post.sh <tag>
# def2spef ss (tt comes from run_pnr.sh), PrimeTime tt / ss with the block ETMs of the same corner (pt_col.tcl) at
# QB_PT_PERIOD (2.0 ns).
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
tag=$1; export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; dir=$QC_BUILD/pnr/$tag
QB_SPEF_CORNERS="ss" "$root/qc18bacc/impl/pnr/run.sh" spef "$tag"
. "$root/flow/tsmc65/common/tool.sh"; . "$dir/kit.env"
set -a; . "$(dirname "$NETLIST")/run.env" 2>/dev/null; set +a
export QC_SDC=$root/qc18bacc/impl/constraints.sdc QC_PT_HOOK= QC_PERIOD=${QB_PT_PERIOD:-2.0} QC_TOP=$TOP QB_HB_ETM_DIR
for c in ${QB_PT_CORNERS:-tt ss}; do
    ( cd "$dir" && QC_PNR_OUT=$dir QC_CORNER=$c qc_tool "pt_col_$c.log" pt_shell -f "$here/pt_col.tcl" )
    echo "PT_COL_DONE $tag $c errors $(grep -c '^Error' $dir/pt_col_$c.log)"; cat "$dir/pt_col_$c.txt"
done
