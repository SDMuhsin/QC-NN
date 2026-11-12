#!/usr/bin/env bash
# Parallel DC + PT (tt, ss) of qb_lane variants on one server:  qc18bacc/impl/lane_batch.sh <P> <top[:hook[:tag[:period]]]> ...
# hook = file name in impl/hooks without .tcl (QC_HOOK, design-specific DC settings), tag default <top>[_<hook>]_tt_p<period>, period default 2.0.
# Logs in $QC_LOGS (default /tmp/$USER/qc18bacc/logs)/<tag>.log; tt compile (QC_CORNER=tt), period 2.0 ns.
HERE=$(cd "$(dirname "$0")" && pwd)
P=$1; shift
export QC_CORNER=tt QC_CORES=${QC_CORES:-2}
LOGS=${QC_LOGS:-/tmp/$USER/qc18bacc/logs}; mkdir -p "$LOGS"
for it in "$@"; do echo "$it"; done | xargs -P "$P" -I{} bash -c '
    IFS=: read -r top hook tag per <<< "{}"
    per=${per:-2.0}; tag=${tag:-${top}${hook:+_$hook}_tt_p$per}
    if [ -n "$hook" ]; then export QC_HOOK='"$HERE"'/hooks/$hook.tcl; fi
    '"$HERE"'/run.sh all "$top" "$per" "$tag" > '"$LOGS"'/$tag.log 2>&1
    echo "LANE_BATCH_DONE $tag"'
