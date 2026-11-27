#!/usr/bin/env bash
# PrimeTime timing of a synthesized netlist at one or more corners:
#   flow/tsmc65/sta/run_pt.sh <syn_run_dir | syn_tag> [corner ...]      (corners default: QC_CORNERS of site.tcl)
# Reads <dir>/run.env + <top>.v (and <top>.spef if DC topographical mode wrote it); one pt_shell per corner,
# constraints regenerated for that corner's library (or QC_SDC).  Pre-CTS, ideal clocks.
# QC_PT_HOOK (optional): Tcl file sourced after the timing reports, with the open summary channel $fh (design reports).
# Output in <dir>: pt_<corner>.log, rpt/pt_<corner>_*.rpt, pt_<corner>.txt (summary).
set -u
. "$(dirname "$0")/../common/tool.sh"
[ $# -ge 1 ] || { sed -n '2,8p' "$0"; exit 1; }
dir=$1; shift
[ -d "$dir" ] || dir=$BUILD/syn/$dir
dir=$(cd "$dir" && pwd) || exit 1
[ -f "$dir/run.env" ] || { echo "no run.env in $dir"; exit 1; }
io=${QC_IO_PCT:-}
set -a; . "$dir/run.env"; set +a
# DC's QC_IO_PCT (a run.env before qc18bacc R107 always has one, default 20; since, only without QC_SDC) is the IO delay of the generated constraints only: with a design SDC
# it is not passed on, so the SDC's own value is in force (qc18bacc common/constraints.sdc: limits.txt; R102, as the
# block PrimeTime since R100) unless the caller's environment sets one
[ -z "${QC_SDC:-}" ] || QC_IO_PCT=$io
corners=${*:-$(sed -n 's/^set ::QC_CORNERS *{\(.*\)}.*/\1/p' "$FLOW/site/site.tcl")}
cd "$dir" || exit 1
fail=0
for c in $corners; do
    QC_OUT=$dir QC_CORNER=$c qc_tool "pt_$c.log" pt_shell -f "$FLOW/sta/pt.tcl"
    rc=$?
    qc_time "pt_$c.log" >> "pt_$c.txt" 2>/dev/null
    # status: rc 0 and no '^Error' line but the allowed ones (common/tool.sh qc_errors; R102: before, only rc, and pt_shell -f
    # exits 0 after a failing command)
    errs=$(grep -c '^Error' "pt_$c.log"); bad=$(qc_errors "pt_$c.log" | grep -c .)
    echo "PT_DONE $(basename "$dir") $c rc $rc errors $bad (allowed $((errs - bad)))"
    qc_errors "pt_$c.log" | head -n 5
    [ -f "pt_$c.txt" ] && sed 's/^/  /' "pt_$c.txt"
    [ $rc = 0 ] && [ "$bad" = 0 ] || fail=1
done
exit $fail
