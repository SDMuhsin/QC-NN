#!/usr/bin/env bash
# OpenROAD place & route of a synthesized netlist (run on the server, from the repository root):
#   flow/tsmc65/pnr/run_pnr.sh <design.cfg> [tag]                  -> $QC_BUILD/pnr/<tag>/  (tag: cfg basename)
# <design.cfg>: Tcl, set P(KEY) value; keys and defaults in pnr/or/lib.tcl (P_DEFAULT), see pnr/README.md.
# Environment (all optional):
#   QC_PNR_SYN     synthesis tag / dir (overrides P(SYN))     QC_PNR_SET  Tcl list {KEY VALUE ...} overrides
#   QC_PNR_FROM / QC_PNR_TO   step range of init floorplan pdn place cts route finish (restart from checkpoints)
#   QC_PNR_POST    0 = skip SPEF / post-route timing / GDS     QC_PNR_THREADS (8)   QC_TOOLS (/tmp/$USER/tools)
#   QC_BUILD       output root (<repo>/build/tsmc65)
# Output: openroad.log (+ .out: stdout incl. Tcl errors), db/<step>.odb, out/<top>.def .v _pg.v .conn _<corner>.spef [.gds], rpt/, rc/, summary.txt
set -u
. "$(dirname "$0")/../common/tool.sh"
[ $# -ge 1 ] || { sed -n '2,12p' "$0"; exit 1; }
cfg=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
tag=${2:-$(basename "$cfg" .cfg)}
out=$BUILD/pnr/$tag
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}
OR=$TOOLS/env/bin/openroad
export QC_PY=$TOOLS/env/bin/python3 QC_PNR_OUT=$out QC_BUILD=$BUILD
[ -x "$OR" ] || { echo "no $OR (run pnr/install_openroad.sh)"; exit 1; }
QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
export QC_KIT
from=${QC_PNR_FROM:-init}
if [ "$from" = init ]; then rm -rf "$out"; fi
mkdir -p "$out/rpt"
printf 'set ::QC_BUILD %s\nsource %s\n' "$BUILD" "$cfg" > "$out/config.tcl"
cd "$out" || exit 1
[ "$from" = init ] && : > summary.txt
t0=$(date +%s)
/usr/bin/time -v -o openroad.log.time "$OR" -no_init -no_splash -exit -log openroad.log "$FLOW/pnr/or/flow.tcl" \
    > openroad.out 2>&1 < /dev/null
rc=$?
[ -f kit.env ] && . ./kit.env
post=${QC_PNR_POST:-1}
if [ $rc = 0 ] && [ "$post" = 1 ] && [ -f "out/$TOP.def" ]; then
    for c in $CORNERS; do
        "$QC_PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_$c.spef" \
            > "def2spef_$c.log" 2>&1 || echo "def2spef $c failed"
        # PrimeTime copy: '/' inside flat instance / net names escaped (names of the flat routed netlist)
        "$QC_PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_${c}_pt.spef" \
            --escape-divider >> "def2spef_$c.log" 2>&1 || echo "def2spef $c (pt) failed"
    done
    "$OR" -no_init -no_splash -exit -log sta_post.log "$FLOW/pnr/or/sta_post.tcl" > sta_post.out 2>&1 < /dev/null
    KL=$TOOLS/kl/bin/klayout
    if [ "$DO_GDS" = 1 ] && [ -x "$KL" ]; then
        "$QC_PY" -I "$FLOW/pnr/py/gds_map.py" "$GDSMAP" "$LEF" rc/klayout.map > gds.log 2>&1
        "$KL" -b -r "$FLOW/pnr/py/gds_merge.py" -rd def_in="$out/out/$TOP.def" -rd lefs="$LEF $MACRO_LEFS" \
            -rd gds="$GDS $MACRO_GDS" -rd layer_map="$out/rc/klayout.map" -rd out="$out/out/$TOP.gds" >> gds.log 2>&1
        grep '^gds_merge' gds.log >> summary.txt || echo "gds_merge FAILED (gds.log)" >> summary.txt
    fi
fi
# DRC / antenna counts from the logs
drc=$(grep -c 'violation type' rpt/drt.drc.rpt 2>/dev/null); drc=${drc:-NA}
ant=$(sed -n 's/.*Found \([0-9]*\) net violations.*/\1/p' openroad.log | tail -1)
antp=$(sed -n 's/.*Found \([0-9]*\) pin violations.*/\1/p' openroad.log | tail -1)
echo "drc_violations $drc antenna_net_violations ${ant:-NA} antenna_pin_violations ${antp:-NA}" >> summary.txt
echo "pnr_wall_s $(( $(date +%s) - t0 )) $(qc_time openroad.log)" >> summary.txt
echo "PNR_DONE $tag rc $rc errors $(grep -c '^\[ERROR' openroad.log)"
sed 's/^/  /' summary.txt
