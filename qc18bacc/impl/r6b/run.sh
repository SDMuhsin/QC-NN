#!/usr/bin/env bash
# R6b full-chip P&R with group template placement (results/r6b.md), on tau from the repository root, QC_BUILD as R5b:
#   qc18bacc/impl/r6b/run.sh fp   <tag>         init (chip.cfg: netlist QB_SYN default r6a_hpw144), macro dump, mplace.py
#                                               (env QB_WEST / QB_SB / QB_NB / QB_WAH), floorplan + pdn
#   qc18bacc/impl/r6b/run.sh prep <tag>         remove_buffers (prep.tcl), netlist dump (impl/r6a/net_dump.tcl) and group
#                                               file grp.txt (impl/r6a/cuts.py --head-south --split-w --groups)
#   qc18bacc/impl/r6b/run.sh grp  <tag> [groups] [seed dir]  standalone placement of each group (grp_place.tcl), in parallel
#   qc18bacc/impl/r6b/run.sh pnr  <tag>         place .. QC_PNR_TO (default finish) from db/pdn (group import: place.tcl)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad
. "$root/flow/tsmc65/common/tool.sh"
step=${1:?step}; tag=${2:?tag}; d=$B/pnr/$tag
QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$TOOLS/env/bin/python3
case $step in
fp)  QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" || exit 1
     ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
     python3 -I "$here/mplace.py" "$d/macros.txt" "$d/mplace.tcl" || exit 1
     QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" ;;
prep) cd "$d" || exit 1
     QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit -log prep.log "$here/prep.tcl" > prep.out 2>&1 < /dev/null || { echo "prep failed"; tail -3 prep.out; exit 1; }
     QB_RUN=$d QB_DB=pdn QB_OUT=$d/dump.txt "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r6a/net_dump.tcl" > net_dump.log 2>&1 < /dev/null
     python3 -I "$root/qc18bacc/impl/r6a/cuts.py" dump.txt grp --head-south --split-w --groups grp.txt
     awk '{n[$2]++} END {for (g in n) print "GROUP_CELLS", g, n[g]}' grp.txt ;;
grp) cd "$d" || exit 1
     for g in ${3:-S WA W N}; do
         QC_PNR_OUT=$d QB_GRP=$g QB_GFILE=$d/grp.txt ${4:+QB_SEED=$4} "$OR" -no_init -no_splash -exit -log grp_$g.log \
             "$here/grp_place.tcl" > grp_$g.out 2>&1 < /dev/null &
     done
     wait; grep -h '^GRP' grp_*.out ;;
pnr) QC_PNR_FROM=${QC_PNR_FROM:-place} "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" ;;
*) sed -n '2,9p' "$0"; exit 1 ;;
esac
echo "R6B_DONE $step $tag"
