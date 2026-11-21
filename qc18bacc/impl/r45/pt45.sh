#!/usr/bin/env bash
# R45: run a PrimeTime Tcl in the env of a routed block run (as impl/r5a/post.sh etm), cwd = private dir.
#   pt45.sh <pnr_run_dir> <corner> <script.tcl> <log> [period]
set -u
d=$1; c=$2; scr=$3; log=$4; per=${5:-6.5}
SNAP=${SNAP:-/tmp/ckp908/qc18bacc/r35_snap}
. "$SNAP/flow/tsmc65/common/tool.sh"
export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
. "$d/kit.env"
set -a; . "$(dirname "$NETLIST")/run.env"; set +a
export QC_SDC=$SNAP/qc18bacc/impl/constraints.sdc QC_PT_HOOK= QC_PERIOD=$per QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c
qc_tool "$log" pt_shell -f "$scr"
echo "PT45 done $(grep -c '^Error' "$log") errors"
