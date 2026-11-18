#!/usr/bin/env bash
# R23: run an OpenROAD dump script read-only on a hub run's checkpoint (same environment as impl/r21/budget.sh orun):
#   qc18bacc/impl/r23/orun23.sh <run dir> <odb> <out file> <tcl> [extra VAR=val ...]
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}
run=$1; db=$2; out=$3; tcl=$4; shift 4
. "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
cd "$run" && env "$@" QC_FLOW=$FLOW QC_PNR_OUT=$run QB_DB=$db QB23_OUT=$out QB12_OUT=$out \
    "$TOOLS/env/bin/openroad" -no_init -no_splash -exit "$tcl" > "$out.log" 2>&1 < /dev/null
echo ORUN23 rc $? $(date +%T)
