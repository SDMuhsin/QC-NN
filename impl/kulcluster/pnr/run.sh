#!/usr/bin/env bash
# P&R of the KUL cluster on the server (from the repository root of a server tree; see README.md):
#   impl/kulcluster/pnr/run.sh pnr [tag]   OpenROAD (flow/tsmc65/pnr/run_pnr.sh kulcluster.cfg) -> $QC_BUILD/pnr/<tag>
#   impl/kulcluster/pnr/run.sh pt  [tag]   PrimeTime post-route timing (run_pt_post.sh) + vectorless power, ss tt ff
# tag: kul_pnr.  QC_BUILD default /tmp/$USER/qcnn_kulsyn/build (synthesis kul_w4.2 under syn/), QC_PNR_THREADS 14.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qcnn_kulsyn/build} QC_PNR_THREADS=${QC_PNR_THREADS:-14}
step=${1:-}; tag=${2:-kul_pnr}
case $step in
pnr) "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/kulcluster.cfg" "$tag" ;;
pt)
    "$root/flow/tsmc65/pnr/run_pt_post.sh" "$tag"
    . "$root/flow/tsmc65/common/tool.sh"
    dir=$QC_BUILD/pnr/$tag
    . "$dir/kit.env"
    set -a; . "$(dirname "$NETLIST")/run.env"; set +a
    cd "$dir" || exit 1
    for c in $CORNERS; do
        QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c qc_tool "pt_power_$c.log" pt_shell -f "$here/pt_power.tcl"
        echo "PT_POWER_DONE $c rc $? $(cat "pt_power_$c.txt" 2>/dev/null | head -1)"
    done ;;
*) sed -n '2,6p' "$0"; exit 1 ;;
esac
