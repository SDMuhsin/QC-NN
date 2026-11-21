#!/usr/bin/env bash
# R42 (results/r42.md): chip-top Calibre LVS with the hard blocks (qb_col_blk / qb_hub / qb_act2_blk) and the top SRAMs as
# LVS BOX black boxes (pins only, abstracts from their LEFs).  Imports R38 / R36 steps (nothing copied):
#   lefstub.py (pin-only .SUBCKT + Verilog stubs) -> lef2gds.py (LEF abstracts -> GDS cells) -> gds36.sh top (DEF merge)
#   -> lvssrc38.sh (pgfix + v2lvs) -> cal36.sh lvs with lvs_case + LVS BOX lines.
#   lvs42.sh <tag> <abs dir> <rundir> [steps "stub agds gds src lvs"]   block LEFs taken from <abs dir> (same names as in
#   the run's MACRO_LEFS), so the final views are used; env QB42_STACK [1] = lef2gds stack cuts for the SRAMs.
set -u
here=$(cd "$(dirname "$0")" && pwd); I=$here/..; root=$(cd "$I/../.." && pwd)
B=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; PY=$TOOLS/env/bin/python3; KL=$TOOLS/kl/bin/klayout
tag=${1:?tag}; A=${2:?abs dir}; r=${3:?rundir}; steps=${4:-"stub agds gds src lvs"}; d=$B/pnr/$tag
mkdir -p "$r"; cd "$r" || exit 1
. "$d/kit.env"
lefs=""; for f in $MACRO_LEFS; do b=$(basename "$f"); case $b in qb_col_blk.lef|qb_hub.lef|qb_act2_blk.lef) f=$A/$b ;; esac; lefs="$lefs $f"; done
echo "LVS42 lefs$lefs"
ts() { echo "LVS42 $1 $(date -u +%T)"; }
for s in $steps; do ts "start $s"; case $s in
stub) "$PY" -I "$I/r38/lefstub.py" "$r/stubs.spi" "$r/stubs.box" $lefs ;;
agds) # blocks: no stack cuts (their PG pins cross on adjacent layers); SRAMs: QB42_STACK [1] (R38 F5: M1-M3 pins at one spot)
     bl=""; ml=""; for f in $lefs; do case $(basename "$f") in qb_col_blk.lef|qb_hub.lef|qb_act2_blk.lef) bl="$bl $f" ;; *) ml="$ml $f" ;; esac; done
     "$KL" -b -r "$I/r38/lef2gds.py" -rd lefs="$LEF $bl" -rd layer_map="$B/r36/gds/kl.map" -rd stack=0 -rd out="$r/abs_blk.gds"
     "$KL" -b -r "$I/r38/lef2gds.py" -rd lefs="$LEF $ml" -rd layer_map="$B/r36/gds/kl.map" -rd stack="${QB42_STACK:-1}" -rd out="$r/abs_mac.gds" ;;
gds) QB36_KITRUN=$tag "$I/r36/gds36.sh" top "$tag" "$r/top.gds" "$r/abs_blk.gds" "$r/abs_mac.gds" ;;
src) "$I/r38/lvssrc38.sh" "$d/out/${TOP}_pg.v" "$r/top.spi" "$r/stubs.spi" ;;
lvs) { echo '/^LVS ISOLATE SHORTS YES/a\'; echo 'LAYOUT CASE YES\'; echo 'SOURCE CASE YES\';
       sed '$!s/$/\\/' "$r/stubs.box"; } > "$r/deck.sed"
     QB36_LVS_SED="-f $r/deck.sed" "$I/r36/cal36.sh" lvs "$r/top.gds" "$TOP" "$r/top.spi" "$r/cal" "${QB42_TURBO:-8}" ;;
esac; ts "done $s"; done
