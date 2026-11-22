#!/usr/bin/env bash
# Block / top GDS for Calibre (results/r36.md, r38.md): flow/tsmc65 gds_map.py + gds_merge.py (via gds_merge.py here: dbu
# 0.001 um for the Calibre decks; LEF OBS -> 255/<n>), run with the klayout Python wheel (kl.sh: klrun.py, layer map $B/drc/r38_map).
#   qc18bacc/flow/signoff/calibre/gds.sh <kitrun> <def> <out.gds> [extra lefs...]   (kitrun = pnr run whose kit.env gives LEF / GDS / GDSMAP)
#   env: QB38_GDS_EXTRA = extra GDS files (e.g. SRAM abstracts)
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/kl.sh"
kitrun=$1; def=$2; out=$3; shift 3
map=$(kl_map "$kitrun") || { echo "GDS38 FAIL layer map"; exit 1; }
/usr/bin/time -f "GDS38 wall %e s rss %M kB" bash -c '. "$1"; shift; kl_run "$@"' - "$here/kl.sh" "$here/gds_merge.py" \
  -rd def_in="$def" -rd lefs="$(kl_kit "$kitrun" LEF) $*" -rd gds="$(kl_kit "$kitrun" GDS) ${QB38_GDS_EXTRA:-}" -rd layer_map="$map" -rd out="$out" \
  || { echo "GDS38 FAIL gds_merge"; exit 1; }
ls -la "$out"
