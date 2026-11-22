#!/usr/bin/env bash
# Block / top GDS for Calibre (results/r36.md, r38.md): flow/tsmc65 gds_map.py + gds_merge.py (via gds_merge.py here: dbu
# 0.001 um for the Calibre decks; LEF OBS -> 255/<n>), run with the klayout Python wheel (klrun.py), layer map in $B/drc/r38_map.
#   qc18bacc/flow/signoff/calibre/gds.sh <kitrun> <def> <out.gds> [extra lefs...]   (kitrun = pnr run whose kit.env gives LEF / GDS / GDSMAP)
#   env: QB38_GDS_EXTRA = extra GDS files (e.g. SRAM abstracts)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../../.." && pwd)
B=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; PY=$TOOLS/env/bin/python3
export PYTHONPATH=$TOOLS/kl_py${PYTHONPATH:+:$PYTHONPATH}
kitrun=$1; def=$2; out=$3; shift 3
kit() { ( cd "$B/pnr/$kitrun" && . ./kit.env && echo "${!1}" ); }
LEF=$(kit LEF); GDS=$(kit GDS); GDSMAP=$(kit GDSMAP)
M=$B/drc/r38_map; mkdir -p "$M"
if [ ! -f "$M/kl.map" ]; then
  "$PY" -I "$root/flow/tsmc65/pnr/py/gds_map.py" "$GDSMAP" "$LEF" "$M/kl0.map"
  awk '{ if ($2 ~ /LEFOBS/) { sub(/,LEFOBS/, "", $2); n++; print; print $1, "LEFOBS", 255, n } else print }' "$M/kl0.map" > "$M/kl.map"
fi
/usr/bin/time -f "GDS38 wall %e s rss %M kB" "$PY" "$here/klrun.py" -b -r "$here/gds_merge.py" \
  -rd def_in="$def" -rd lefs="$LEF $*" -rd gds="$GDS ${QB38_GDS_EXTRA:-}" -rd layer_map="$M/kl.map" -rd out="$out"
ls -la "$out"
