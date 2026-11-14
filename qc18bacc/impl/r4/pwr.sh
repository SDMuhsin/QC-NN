#!/bin/bash
# R4 PTPX on a tau host:  impl/r4/pwr.sh <syn_dir> <saif> <sim_period_ns> <out_dir> <period_ns>...
# Rescales the SAIF to each period (saif_scale.py: same toggles per cycle) and runs pt_power.tcl once for all periods
# (tt, netlist + DC topo SPEF of <syn_dir>, impl/constraints.sdc).  Reports stay in <out_dir> on the host.
set -eu
H=$(cd "$(dirname "$0")" && pwd); R=$(cd "$H/../../.." && pwd)
S=$1; SAIF=$2; SP=$3; D=$4; shift 4
mkdir -p "$D"; cd "$D"
RUNS=""
for p in "$@"; do
    python3 -I "$H/saif_scale.py" "$(python3 -c "print($p / $SP)")" "$SAIF" > "w_$p.saif"
    RUNS="$RUNS $p $D/w_$p.saif $D/p$p"
done
. "$S/run.env"
tcsh -f -c "source $R/flow/tsmc65/site/site.csh; setenv QC_FLOW $R/flow/tsmc65; setenv SYN $S; setenv QC_SDC $R/qc18bacc/impl/constraints.sdc; setenv QC_EXTRA_DB_TT \"$QC_EXTRA_DB_TT\"; setenv R4_RUNS \"$RUNS\"; pt_shell -f $H/pt_power.tcl >& pt.log"
grep -E "^Error" pt.log | sort | uniq -c | head
rm -f w_*.saif
echo PWR_DONE "$@"
