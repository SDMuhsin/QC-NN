#!/usr/bin/env bash
# Area groups + xbar fan-in (impl/v4/area_groups.tcl) of a synthesised QC18-ACC netlist, run on its build host:
#   qc18acc/impl/v4/area_run.sh <host> <syn_tag>   -> qc18acc/impl/results/<tag>/area_groups.txt
# (v4 runs get the same file from the tt PT hook; this script also measures v2 / v3 netlists for the comparison.)
set -euo pipefail
H=${1:?host}; T=${2:?syn_tag}
RDIR=${QC_RDIR:-/tmp/ckp908/qc18acc}; R=$RDIR/repo; SYN=$RDIR/build/syn/$T
OUTL=$(cd "$(dirname "$0")/.." && pwd)/results/$T; mkdir -p "$OUTL"
DBTT=$(ssh "$H" ". $SYN/run.env; echo \$QC_EXTRA_DB_TT")
ssh "$H" "set -e; cd $SYN; tcsh -f -c 'source $R/flow/tsmc65/site/site.csh; setenv QC_FLOW $R/flow/tsmc65; setenv SYN $SYN; \
  setenv QC_EXTRA_DB_TT \"$DBTT\"; pt_shell -f $R/qc18acc/impl/v4/area_run.tcl >& area_run.log'; grep -E '^Error' area_run.log | head -3; cat rpt/area_groups.txt"
scp -q "$H:$SYN/rpt/area_groups.txt" "$OUTL/area_groups.txt"
echo "-> $OUTL/area_groups.txt"
