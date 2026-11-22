#!/usr/bin/env bash
# Post-route hold (+ optional setup) ECO of a routed run (results/r35.md, r37.md, r38.md): OpenROAD SPEF of the routed DEF
# (QC_SPEF_ORFIX 1), repair/hold_eco.tcl (repair_timing -hold on that SPEF, rip + GRT + DR, finish; QB35_* / QB37_* knobs
# from the caller, e.g. blocks/act/run.sh, blocks/hub/run.sh), then the SPEFs of the new DEF (OpenROAD copy QC_SPEF_ORFIX 1,
# PrimeTime copy QC_SPEF_UNESC [1]).
#   qc18bacc/flow/repair/hold_eco.sh <tag>      (repair corners QB35_CORNERS [tt ss]: OpenROAD SPEF out/<top>_<c>_or.spef each;
#                                               QB50_MPA 1: the detailed route runs in a second process, r35_hold_dr.log)
set -u
. "$(dirname "$0")/../common/env.sh"
tag=${1:?tag}; d=$B/pnr/$tag
echo "R35_STEP hold $tag - $(date +%T)"
( . "$ROOT/flow/tsmc65/common/tool.sh"; cd "$d" && . ./kit.env
  for c in ${QB35_CORNERS:-tt ss}; do
    QC_SPEF_ORFIX=1 "$PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_${c}_or.spef" > def2spef_${c}_or.log 2>&1 || exit 1
  done ) || exit 1
"$QBF/common/or.sh" "$tag" "$QBF/repair/hold_eco.tcl" r35_hold.log
lg="$d/r35_hold.log"
if grep -q "R35_HOLD mpa saved" "$lg"; then   # QB50_MPA: detailed route of the edited access points in a fresh process
  QB50_MPA_PASS=dr "$QBF/common/or.sh" "$tag" "$QBF/repair/hold_eco.tcl" r35_hold_dr.log; lg="$lg $d/r35_hold_dr.log"
fi
grep -h "R35_HOLD" $lg | grep -v "^\[" ; cat $lg | grep -q "R35_HOLD saved" || exit 0
( . "$ROOT/flow/tsmc65/common/tool.sh"; cd "$d" && . ./kit.env
  for c in $CORNERS; do
    QC_SPEF_ORFIX=1 "$PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_$c.spef" > "def2spef_$c.log" 2>&1 || echo "def2spef $c failed"
    QC_SPEF_UNESC=${QC_SPEF_UNESC:-1} "$PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_${c}_pt.spef" --escape-divider >> "def2spef_$c.log" 2>&1 || echo "def2spef $c (pt) failed"
  done )
echo "R35_DONE hold $tag $(date +%T)"
