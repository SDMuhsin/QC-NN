#!/usr/bin/env bash
# R29: run an OpenROAD tcl in a run dir with the flow env (as impl/r28/ant28.sh).  On tau from the snapshot root:
#   qc18bacc/impl/r29/or29.sh <tag> <script.tcl> <log>   (env passes through, e.g. R29_* knobs)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad; PY=$TOOLS/env/bin/python3
export QB9_W=${QB9_W:-$B/r26_w} QB_SYN=${QB_SYN:-r26_ptr}
export R29_HERE=$here
tag=${1:?tag}; scr=${2:?tcl}; log=${3:?log}; d=$B/pnr/$tag
. "$root/flow/tsmc65/common/tool.sh"; cd "$d" || exit 1
QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY QC_PNR_OUT=$d QC_FLOW=$FLOW
/usr/bin/time -v "$OR" -no_init -no_splash -exit -log "$log" "$scr" > "$log.out" 2> "$log.time" < /dev/null
echo R29_OR_DONE $tag $(basename "$scr") $(date +%T)
