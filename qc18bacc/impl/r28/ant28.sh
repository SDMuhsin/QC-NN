#!/usr/bin/env bash
# R28 (results/r28.md): post-DR antenna repair (opt-in, after impl/r28/eco28.sh).  On tau from the snapshot root:
#   qc18bacc/impl/r28/ant28.sh <tag>   db/route_dr.odb -> db/route_dr_preant.odb (copy), ant28.tcl (repair_antennas +
#                                      detailed_route on the routed db + check_antennas; when clean: route_dr / route /
#                                      finish saves), then SPEF of out/<top>.def (as impl/r8/run.sh dr) + summary line
# Env as impl/r21/run.sh dr (QB8_DR_FILL 0, QB_ANT_CHECK 0); QB28_ANT_ITER [1], QB28_ANT_DR [8], QB28_ANT_SAVE [1].
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad; PY=$TOOLS/env/bin/python3
export QB9_W=${QB9_W:-$B/r26_w} QB_SYN=${QB_SYN:-r26_ptr}
tag=${1:?tag}; d=$B/pnr/$tag
. "$root/flow/tsmc65/common/tool.sh"; cd "$d" || exit 1
QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY QC_PNR_OUT=$d QC_FLOW=$FLOW
[ -s db/route_dr_preant.odb ] || cp db/route_dr.odb db/route_dr_preant.odb
QB8_DR_FILL=0 QB_ANT_CHECK=0 QB8_DR_THREADS=${THR:-16} "$OR" -no_init -no_splash -exit -log ant28.log "$here/ant28.tcl" > ant28.out 2>&1 < /dev/null
grep -h "R28_ANT" ant28.log
grep -q "R28_ANT saved" ant28.log || { echo R28_ANT_NOT_SAVED; exit 1; }
. ./kit.env
for c in $CORNERS; do
    "$QC_PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_$c.spef" > "def2spef_$c.log" 2>&1 || echo "def2spef $c failed"
    "$QC_PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_${c}_pt.spef" --escape-divider >> "def2spef_$c.log" 2>&1 || echo "def2spef $c (pt) failed"
done
echo "ant28 $(grep -h 'R28_ANT post' ant28.log)" | tee -a summary.txt
echo R28_ANT_DONE $(date +%T)
