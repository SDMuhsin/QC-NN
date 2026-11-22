#!/usr/bin/env bash
# Run an OpenROAD Tcl script in a P&R run dir with the flow environment (QC_FLOW, QC_KIT, QC_PNR_OUT, QC_PY):
#   qc18bacc/flow/common/or.sh <tag> <script.tcl> <log>    ($B/pnr/<tag>; env passes through, e.g. R29_* knobs)
# Scripts that re-source the run's config.tcl see the caller's design environment (QB_SYN, QB9_W, ...: each
# blocks/<b>/run.sh exports its own).
set -u
. "$(dirname "$0")/env.sh"
tag=${1:?tag}; scr=${2:?tcl}; log=${3:?log}; d=$B/pnr/$tag
. "$ROOT/flow/tsmc65/common/tool.sh"; cd "$d" || exit 1
QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY
export QC_PNR_OUT=$d QC_FLOW=$FLOW
/usr/bin/time -v "$OR" -no_init -no_splash -exit -log "$log" "$scr" > "$log.out" 2> "$log.time" < /dev/null
echo R29_OR_DONE $tag $(basename "$scr") $(date +%T)
