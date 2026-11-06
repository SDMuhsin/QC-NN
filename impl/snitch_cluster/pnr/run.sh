#!/usr/bin/env bash
# P&R of the Snitch FP cluster on the server (from the repository root of a server tree; see README.md):
#   impl/snitch_cluster/pnr/run.sh pnr [tag]   OpenROAD (flow/tsmc65/pnr/run_pnr.sh snitch_fp.cfg) -> $QC_BUILD/pnr/<tag>
#   impl/snitch_cluster/pnr/run.sh pt  [tag] [corners]   PrimeTime post-route timing (pt_post.tcl) + vectorless power
# tag: sn_fp.  QC_BUILD default /tmp/$USER/qcnn/build (synthesis fp_p5.0_wlm under syn/), QC_PNR_THREADS 16.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qcnn/build} QC_PNR_THREADS=${QC_PNR_THREADS:-16}
step=${1:-}; tag=${2:-sn_fp}
case $step in
pnr) "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/snitch_fp.cfg" "$tag" ;;
pt)
    # as flow/tsmc65/pnr/run_pt_post.sh (pt_post.tcl per corner) + pt_power.tcl, with the constraints file of the
    # synthesis run.env replaced by this tree's copy when that path (NFS home) is not readable
    . "$root/flow/tsmc65/common/tool.sh"
    dir=$QC_BUILD/pnr/$tag
    . "$dir/kit.env"
    set -a; . "$(dirname "$NETLIST")/run.env"; set +a      # QC_PERIOD, QC_SDC, QC_EXTRA_DB_* (macro .db)
    [ -r "${QC_SDC:-}" ] || export QC_SDC=$root/impl/snitch_cluster/constraints.sdc
    cd "$dir" || exit 1
    for c in ${3:-$CORNERS}; do
        QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c QC_SDC_FILE=$SDC qc_tool "pt_post_$c.log" pt_shell -f "$root/flow/tsmc65/pnr/pt_post.tcl"
        echo "PT_POST_DONE $c rc $? errors $(grep -c '^Error' "pt_post_$c.log")"
        QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c qc_tool "pt_power_$c.log" pt_shell -f "$here/pt_power.tcl"
        echo "PT_POWER_DONE $c rc $? $(head -1 "pt_power_$c.txt" 2>/dev/null)"
    done ;;
*) sed -n '2,6p' "$0"; exit 1 ;;
esac
