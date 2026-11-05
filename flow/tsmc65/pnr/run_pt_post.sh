#!/usr/bin/env bash
# PrimeTime post-route check of a pnr/run_pnr.sh result:  flow/tsmc65/pnr/run_pt_post.sh <pnr_tag | pnr_dir> [corner ...]
# Reads <dir>/out/<top>.v and <dir>/out/<top>_<corner>_pt.spef; constraints as sta/run_pt.sh (from the synthesis
# run.env next to the netlist, else the DC SDC), propagated clocks.
# QC_EXTRA_DB_SS / _TT / _FF: macro .db files (as for sta/run_pt.sh).  Output: <dir>/pt_post_<corner>.{log,txt}, rpt/.
set -u
. "$(dirname "$0")/../common/tool.sh"
[ $# -ge 1 ] || { sed -n '2,6p' "$0"; exit 1; }
dir=$1; shift
[ -d "$dir" ] || dir=$BUILD/pnr/$dir
dir=$(cd "$dir" && pwd) || exit 1
[ -f "$dir/kit.env" ] || { echo "no kit.env in $dir"; exit 1; }
. "$dir/kit.env"
syn=$(dirname "$NETLIST")
[ -f "$syn/run.env" ] && { set -a; . "$syn/run.env"; set +a; }
corners=${*:-$CORNERS}
cd "$dir" || exit 1
for c in $corners; do
    QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c QC_SDC_FILE=$SDC qc_tool "pt_post_$c.log" pt_shell -f "$FLOW/pnr/pt_post.tcl"
    rc=$?
    echo "PT_POST_DONE $(basename "$dir") $c rc $rc errors $(grep -c '^Error' "pt_post_$c.log")"
    [ -f "pt_post_$c.txt" ] && sed 's/^/  /' "pt_post_$c.txt"
done
