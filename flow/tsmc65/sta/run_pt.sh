#!/usr/bin/env bash
# PrimeTime timing of a synthesized netlist at one or more corners:
#   flow/tsmc65/sta/run_pt.sh <syn_run_dir | syn_tag> [corner ...]      (corners default: QC_CORNERS of site.tcl)
# Reads <dir>/run.env + <top>.v (and <top>.spef if DC topographical mode wrote it); one pt_shell per corner,
# constraints regenerated for that corner's library (or QC_SDC).  Pre-CTS, ideal clocks.
# Output in <dir>: pt_<corner>.log, rpt/pt_<corner>_*.rpt, pt_<corner>.txt (summary).
set -u
. "$(dirname "$0")/../common/tool.sh"
[ $# -ge 1 ] || { sed -n '2,7p' "$0"; exit 1; }
dir=$1; shift
[ -d "$dir" ] || dir=$BUILD/syn/$dir
dir=$(cd "$dir" && pwd) || exit 1
[ -f "$dir/run.env" ] || { echo "no run.env in $dir"; exit 1; }
set -a; . "$dir/run.env"; set +a
corners=${*:-$(sed -n 's/^set ::QC_CORNERS *{\(.*\)}.*/\1/p' "$FLOW/site/site.tcl")}
cd "$dir" || exit 1
for c in $corners; do
    QC_OUT=$dir QC_CORNER=$c qc_tool "pt_$c.log" pt_shell -f "$FLOW/sta/pt.tcl"
    rc=$?
    qc_time "pt_$c.log" >> "pt_$c.txt" 2>/dev/null
    echo "PT_DONE $(basename "$dir") $c rc $rc errors $(grep -c '^Error' "pt_$c.log")"
    [ -f "pt_$c.txt" ] && sed 's/^/  /' "pt_$c.txt"
done
