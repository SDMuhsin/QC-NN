#!/usr/bin/env bash
# Detailed route + finish of a globally routed run in a fresh OpenROAD process (route/dr.tcl on db/grt.odb + route.guide;
# results/r8.md, r36.md), with an RSS / swap log (rpt/dr_rss.txt), then the SPEFs of the P&R corners (OpenROAD + PrimeTime
# copies) and the DRC / antenna counts in summary.txt.
#   qc18bacc/flow/route/dr.sh <tag>     env: QB_DR_ITER, QB8_DR_THREADS, QB8_DR_FILL, QB_DR_ARGS (route/dr.tcl)
# Configs re-sourced by dr.tcl see the caller's design environment (blocks/<b>/run.sh).
set -u
. "$(dirname "$0")/../common/env.sh"
tag=${1:?tag}; d=$B/pnr/$tag
. "$ROOT/flow/tsmc65/common/tool.sh"; cd "$d" || exit 1
QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY QC_PNR_OUT=$d QC_BUILD=$B
( while :; do r=$(ps -C openroad -o rss= | sort -n | tail -1); echo "$(date +%T) rss_mb $(( ${r:-0} / 1024 )) swap_mb $(free -m | awk '/Swap/{print $3}')"; sleep 60; done ) > rpt/dr_rss.txt 2>&1 &
mon=$!
/usr/bin/time -v -o dr.log.time "$OR" -no_init -no_splash -exit -log dr.log "$QBF/route/dr.tcl" > dr.out 2>&1 < /dev/null
echo "DR rc $? errors $(grep -c '^\[ERROR' dr.log)"; kill $mon; . ./kit.env
for c in $CORNERS; do
    "$QC_PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_$c.spef" > "def2spef_$c.log" 2>&1 || echo "def2spef $c failed"
    "$QC_PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_${c}_pt.spef" --escape-divider >> "def2spef_$c.log" 2>&1 || echo "def2spef $c (pt) failed"
done
drc=$(grep -c 'violation type' rpt/drt.drc.rpt 2>/dev/null); ant=$(sed -n 's/.*Found \([0-9]*\) net violations.*/\1/p' dr.log | tail -1)
echo "dr drc_violations ${drc:-NA} antenna_net_violations ${ant:-NA} $(grep -h 'Maximum resident' dr.log.time)" | tee -a summary.txt
