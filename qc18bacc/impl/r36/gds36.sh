#!/usr/bin/env bash
# R36 (results/r36.md): GDS for Calibre sign-off, KLayout flow/tsmc65/pnr/py/gds_merge.py (imported, not copied).
#   gds36.sh blk <def> <out.gds> [lefs...]       a routed block DEF + std-cell GDS -> block GDS
#   gds36.sh top <run tag> <out.gds> <blk.gds...> top DEF + std-cell GDS + block GDS; SRAMs have no layout in the kit
#                                                 (front-end licence): their LEF pins are written on the pin layers and
#                                                 their LEF OBS on layer 255/<n> (not a mask layer), so DRC / LVS see
#                                                 only the top's own metal around them
# Layer map: flow gds_map.py (Virtuoso stream map of the kit) with LEFOBS moved to 255/<layer index>.
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
. "$root/flow/tsmc65/common/tool.sh"
B=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; PY=$TOOLS/env/bin/python3; KL=$TOOLS/kl/bin/klayout
QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT
mode=${1:?blk|top}; shift
kit() { ( cd "$B/pnr/${QB36_KITRUN:-r36_t1}" && . ./kit.env && echo "${!1}" ); }
LEF=$(kit LEF); GDS=$(kit GDS); GDSMAP=$(kit GDSMAP)
M=$B/r36/gds; mkdir -p "$M"
if [ ! -f "$M/kl.map" ]; then
  "$PY" -I "$FLOW/pnr/py/gds_map.py" "$GDSMAP" "$LEF" "$M/kl0.map"
  awk '{ if ($2 ~ /LEFOBS/) { sub(/,LEFOBS/, "", $2); n++; print; print $1, "LEFOBS", 255, n } else print }' "$M/kl0.map" > "$M/kl.map"
fi
case $mode in
blk) def=$1; out=$2; shift 2
     "$KL" -b -r "${QB36_GDSPY:-$here/gds_merge36.py}" -rd def_in="$def" -rd lefs="$LEF $*" -rd gds="$GDS" -rd layer_map="$M/kl.map" -rd out="$out" ;;
top) tag=$1; out=$2; shift 2; d=$B/pnr/$tag; ( cd "$d" && . ./kit.env
     "$KL" -b -r "$here/gds_merge36.py" -rd def_in="$d/out/$TOP.def" -rd lefs="$LEF $MACRO_LEFS" -rd gds="$GDS $*" \
         -rd layer_map="$M/kl.map" -rd out="$out" ) ;;
esac
ls -la "${out:-}"
