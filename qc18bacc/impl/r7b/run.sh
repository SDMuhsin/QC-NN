#!/usr/bin/env bash
# R7b full-chip placement experiment (results/r7b.md), on tau from the repository root, QC_BUILD as R6c:
#   qc18bacc/impl/r7b/run.sh etm                one-time: $QC_BUILD/r7b_blk = r5b_blk with the P&R ETMs fixed (etm_fix.py)
#   qc18bacc/impl/r7b/run.sh clone  <tag> <src> <step>   as impl/r6c/run.sh clone
#   qc18bacc/impl/r7b/run.sh fp     <tag>       init, macro dump, impl/r6b/mplace.py (QB_SB / QB_NB / QB_WAH ...),
#                                               groups.py (QB7_* env, QB7_PINS), floorplan + pdn (impl/r7b/chip.cfg)
#   qc18bacc/impl/r7b/run.sh prep   <tag>       remove_buffers (impl/r6b/prep.tcl)
#   qc18bacc/impl/r7b/run.sh slice  <tag> <dump> <grp>   impl/r7b/slice.py -> <run>/grp7.txt, slice_area.txt
#   qc18bacc/impl/r7b/run.sh groups <tag>       groups.py on <run>/mplace.tcl -> mplace.tcl.groups (QB7_* env)
#   qc18bacc/impl/r7b/run.sh grp    <tag> [groups]   impl/r6b/grp_place.tcl per group (QB_GFILE <run>/grp7.txt),
#                                               QB7_PAR [4] at a time; QB_SEED / QB_GDENS / QB_GDPL / QB_POS_TAG from env
#   qc18bacc/impl/r7b/run.sh pnr    <tag>       QC_PNR_FROM (place) .. QC_PNR_TO with impl/r7b/chip.cfg
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad; PY=$TOOLS/env/bin/python3
step=${1:?step}; tag=${2:-}; d=$B/pnr/$tag
case $step in
etm) mkdir -p "$B/r7b_blk" && cd "$B/r7b_blk" || exit 1
     for f in ../r5b_blk/*; do case $f in *_ins.lib) ;; *) ln -sf "$f" .;; esac; done
     for c in tt ss ff; do "$PY" -I "$here/etm_fix.py" ../r5b_blk/qb_col_blk_${c}_ins.lib qb_col_blk_${c}_ins.lib; done ;;
clone) "$here/../r6c/run.sh" clone "$tag" "${3:?src}" "${4:?step}" || exit 1 ;;
fp)  . "$root/flow/tsmc65/common/tool.sh"
     QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" || exit 1
     ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
     "$PY" -I "$root/qc18bacc/impl/r6b/mplace.py" "$d/macros.txt" "$d/mplace.tcl" || exit 1
     "$PY" -I "$here/groups.py" "$d/mplace.tcl" "$d/mplace.tcl.groups" || exit 1
     QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" ;;
prep) . "$root/flow/tsmc65/common/tool.sh"; cd "$d" || exit 1
     QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY
     QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit -log prep.log "$root/qc18bacc/impl/r6b/prep.tcl" > prep.out 2>&1 < /dev/null || { echo "prep failed"; tail -3 prep.out; exit 1; } ;;
slice) cd "$d" || exit 1; "$PY" -I "$here/slice.py" "${3:?dump}" "${4:?grp}" grp7.txt slice_area.txt ;;
groups) "$PY" -I "$here/groups.py" "$d/mplace.tcl" "$d/mplace.tcl.groups" ;;
grp) . "$root/flow/tsmc65/common/tool.sh"; cd "$d" || exit 1
     QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY
     n=0
     for g in ${3:-S0 S1 S2 S3 S4 S5 S6 S7 SX WA W N}; do
         QC_PNR_OUT=$d QB_GRP=$g QB_GFILE=${QB_GFILE:-$d/grp7.txt} "$OR" -no_init -no_splash -exit -log grp_$g.log \
             "$root/qc18bacc/impl/r6b/grp_place.tcl" > grp_$g.out 2>&1 < /dev/null &
         n=$((n + 1)); [ $((n % ${QB7_PAR:-4})) -eq 0 ] && wait
     done
     wait; grep -h '^GRP' grp_*.out ;;
pnr) QC_PNR_FROM=${QC_PNR_FROM:-place} "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" ;;
*) sed -n '2,13p' "$0"; exit 1 ;;
esac
echo "R7B_DONE $step $tag"
