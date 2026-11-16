#!/usr/bin/env bash
# R8 full-chip route shakedown (results/r8.md), on tau from the repository root, QC_BUILD as R6c / R7b:
#   qc18bacc/impl/r8/run.sh fp   <tag>     init (impl/r8/chip.cfg, netlist QB_SYN [r7h_rp]), macro dump, impl/r8/mplace.py
#                                          (QB_SB [400] QB_WAH [1980]), impl/r8/groups.py (QB8_*), floorplan + pdn
#   qc18bacc/impl/r8/run.sh prep <tag>     remove_buffers (impl/r6b/prep.tcl, QB_RMBUF [0]), netlist dump, impl/r6a/cuts.py
#                                          groups (--head-south --split-w) -> grp0.txt, impl/r8/pgrp.py -> grp.txt (P0..P7; QB8_NOP 1: none)
#   qc18bacc/impl/r8/run.sh grp  <tag> [groups]   impl/r6b/grp_place.tcl per group, QB8_PAR [4] at a time
#                                          (QB_GDENS [0.6], QB_GDPL [1], QB_POS_TAG [_L]; QB_SEED from env)
#   qc18bacc/impl/r8/run.sh pnr  <tag>     QC_PNR_FROM [place] .. route with the R6c_h / R7b recipe env (defaults below;
#                                          QB_GRT_STOP 1: checkpoint db/grt.odb and exit after GRT)
#   qc18bacc/impl/r8/run.sh dr   <tag>     detailed route in a fresh process (impl/r8/dr.tcl = r6c's + QB8_DR_FILL /
#                                          QB8_DR_THREADS) + SPEF, RSS log rpt/dr_rss.txt
#   qc18bacc/impl/r8/run.sh pt   <tag>     PrimeTime tt + ss per class (impl/r6c/run.sh ptp)
#   qc18bacc/impl/r8/run.sh probe <tag> <db> [tcl]  read-only probe (default probe_west.tcl -> rpt/probe_west.txt)
#   qc18bacc/impl/r8/run.sh ovf  <tag>     impl/r8/ovf.py on rpt/gr_congestion.rpt -> rpt/ovf_r8.txt
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad; PY=$TOOLS/env/bin/python3
step=${1:?step}; tag=${2:?tag}; d=$B/pnr/$tag
export QB_SYN=${QB_SYN:-r7h_rp}
kit() { . "$root/flow/tsmc65/common/tool.sh"
        QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY; }
case $step in
fp)  . "$root/flow/tsmc65/common/tool.sh"
     QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" || exit 1
     ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
     QB_SB=${QB_SB:-400} QB_WAH=${QB_WAH:-1980} "$PY" -I "$here/mplace.py" "$d/macros.txt" "$d/mplace.tcl" || exit 1
     QB8_WAH=${QB8_WAH:-1980} "$PY" -I "$here/groups.py" "$d/mplace.tcl" "$d/mplace.tcl.groups" || exit 1
     QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" ;;
prep) kit; cd "$d" || exit 1
     QB_RMBUF=${QB_RMBUF:-0} QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit -log prep.log "$root/qc18bacc/impl/r6b/prep.tcl" > prep.out 2>&1 < /dev/null || { echo "prep failed"; tail -3 prep.out; exit 1; }
     QB_RUN=$d QB_DB=pdn QB_OUT=$d/dump.txt "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r6a/net_dump.tcl" > net_dump.log 2>&1 < /dev/null
     python3 -I "$root/qc18bacc/impl/r6a/cuts.py" dump.txt grp --head-south --split-w --groups grp0.txt > cuts.log 2>&1 || { tail -3 cuts.log; exit 1; }
     if [ "${QB8_NOP:-0}" = 1 ] && [ "${QB8_DIST_W:-0}" != 1 ]; then cp grp0.txt grp.txt; else "$PY" -I "$here/pgrp.py" grp0.txt grp.txt | tee pgrp.log; fi
     awk '{n[$2]++} END {for (g in n) print "GROUP_CELLS", g, n[g]}' grp.txt | sort ;;
grp) kit; cd "$d" || exit 1
     n=0
     for g in ${3:-$(awk '{print $1}' mplace.tcl.groups)}; do
         QC_PNR_OUT=$d QB_GRP=$g QB_GFILE=$d/grp.txt QB_GDENS=${QB_GDENS:-0.6} QB_GDPL=${QB_GDPL:-1} QB_POS_TAG=${QB_POS_TAG:-_L} \
             QC_PNR_THREADS=${QC_PNR_THREADS:-4} "$OR" -no_init -no_splash -exit -log grp_$g.log \
             "$root/qc18bacc/impl/r6b/grp_place.tcl" > grp_$g.out 2>&1 < /dev/null &
         n=$((n + 1)); [ $((n % ${QB8_PAR:-4})) -eq 0 ] && wait
     done
     wait; grep -h '^GRP' grp_*.out ;;
pnr) cd "$root" || exit 1
     export QB_SNAP=${QB_SNAP:-1} QB_SNAP3=${QB_SNAP3:-1} QB_SPREAD=${QB_SPREAD:-2} QB_SPREAD3=${QB_SPREAD3:-1} \
        QB_SPREAD_ALL=${QB_SPREAD_ALL:-1} QB_ICG=${QB_ICG:-1} QB_EST_RC=${QB_EST_RC:-0.73 0.28} QB_POS_TAG=${QB_POS_TAG:-_L} \
        QB_NOHOLD=${QB_NOHOLD:-1} QB_SKIP_RT=${QB_SKIP_RT:-1} QB_GRT_ALLOW=${QB_GRT_ALLOW:-1} QB_GRT_STOP=${QB_GRT_STOP:-1} \
        QB7_GR_ITER=${QB7_GR_ITER:-3} QB7_GROUPS=${QB7_GROUPS:-$(awk '{printf "%s ", $1}' "$d/mplace.tcl.groups")}
     QC_PNR_FROM=${QC_PNR_FROM:-place} "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" ;;
dr)  # as impl/r6c/run.sh dr, with impl/r8/dr.tcl (QB8_DR_FILL / QB8_DR_THREADS) and an RSS / swap log (rpt/dr_rss.txt)
     . "$root/flow/tsmc65/common/tool.sh"; cd "$d" || exit 1
     QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY QC_PNR_OUT=$d QC_BUILD=$B
     ( while :; do r=$(ps -C openroad -o rss= | sort -n | tail -1); echo "$(date +%T) rss_mb $(( ${r:-0} / 1024 )) swap_mb $(free -m | awk '/Swap/{print $3}')"; sleep 60; done ) > rpt/dr_rss.txt 2>&1 &
     mon=$!
     /usr/bin/time -v -o dr.log.time "$OR" -no_init -no_splash -exit -log dr.log "$here/dr.tcl" > dr.out 2>&1 < /dev/null
     echo "DR rc $? errors $(grep -c '^\[ERROR' dr.log)"; kill $mon; . ./kit.env
     for c in $CORNERS; do
         "$QC_PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_$c.spef" > "def2spef_$c.log" 2>&1 || echo "def2spef $c failed"
         "$QC_PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_${c}_pt.spef" --escape-divider >> "def2spef_$c.log" 2>&1 || echo "def2spef $c (pt) failed"
     done
     drc=$(grep -c 'violation type' rpt/drt.drc.rpt 2>/dev/null); ant=$(sed -n 's/.*Found \([0-9]*\) net violations.*/\1/p' dr.log | tail -1)
     echo "dr drc_violations ${drc:-NA} antenna_net_violations ${ant:-NA} $(grep -h 'Maximum resident' dr.log.time)" | tee -a summary.txt ;;
pt)  QB_PT_EXTRA=${QB_PT_EXTRA-$root/qc18bacc/impl/r6b/pt_extra.tcl} "$root/qc18bacc/impl/r6c/run.sh" ptp "$tag" ;;
probe) cd "$d" || exit 1; QB_RUN=$d QB_DB=${3:?db} "$OR" -no_init -no_splash -exit "$here/${4:-probe_west.tcl}" > probe_${3}.log 2>&1 < /dev/null; tail -2 probe_${3}.log ;;
ovf) dw=$(sed -n 's/.*DIE_AREA) {0 0 \([0-9.]*\) \([0-9.]*\)}.*/\1 \2/p' "$d/mplace.tcl")
     ya=$(awk '/__u_col /{print $3; exit}' "$d/mplace.tcl")
     QB8_XA=${QB8_XA:-$(awk '/__u_col /{print $2; exit}' "$d/mplace.tcl")} QB8_YA=$ya QB8_YT=$(echo "$ya + 3110" | bc) "$PY" -I "$here/ovf.py" "$d/rpt/gr_congestion.rpt" "$tag" 3.0 $dw | tee "$d/rpt/ovf_r8.txt" ;;
*) sed -n '2,18p' "$0"; exit 1 ;;
esac
echo "R8_DONE $step $tag"
