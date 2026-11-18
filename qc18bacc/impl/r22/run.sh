#!/usr/bin/env bash
# R22 (results/r22.md): south hub qb_hub on the taller die (QB_SB 649 -> H 1950.2) with floorplan variants
# (impl/r22/mplace22.py QB22_FP a | pn), a pre-route wire-budget gate, then production for the passing variant.
# Steps imported from impl/r15 (fp, grt), impl/r21 (hooks, budget, dr / post / abs / ant), not copied.  On tau from the
# snapshot root:
#   qc18bacc/impl/r22/run.sh gate <tag>   fp (run15.sh fp with QB15_MPLACE = mplace22.py) + place (TD, fo 32, R21 hooks)
#                                         -> db/place.odb; GRT of place.odb (impl/r15 grt15.tcl, QB_GI [10] iterations,
#                                         QB15_GADJ_L "M5-M9 0.10") -> grt_pl; budget.sh (cuts21 + q1) -> bud_pl/
#   qc18bacc/impl/r22/run.sh bud <tag>    budget.sh only (cuts21 regions from the run's S rows: QB21_SROWS)
#   qc18bacc/impl/r22/run.sh sq <tag>     S-macro net spans on db/place.odb (sq22.tcl / sq22.py)
#   qc18bacc/impl/r22/run.sh prod <tag>   CTS -> post-CTS repair (QB_IO_LAT) -> GRT + antenna repair (R21 hooks) -> db/grt.odb
#                                         (opt-in R24: QB22_FROM start step [cts], QB22_SET_X extra QC_PNR_SET pairs)
#   qc18bacc/impl/r22/run.sh dr|post|ant <tag>   = impl/r21/run.sh (abstract dir prefix r22)
#   qc18bacc/impl/r22/run.sh abs <tag>    impl/r21/run.sh abs + ring LEF (impl/r5b/lef_ring.py) -> $QC_BUILD/r22_<tag>/
#   qc18bacc/impl/r22/run.sh fin <tag>    ant | post -> abs (+ ring LEF)
# Env defaults = impl/r21/run.sh defaults + QB_SB 649, QB21_MAXFO 32, QB22_FP a, QB_GI 10.
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
export QB_SB=${QB_SB:-649} QB21_MAXFO=${QB21_MAXFO:-32} QB22_FP=${QB22_FP:-a} QB15_FP=${QB15_FP:-mid}
export QB15_MPLACE=${QB22_MPLACE:-$here/mplace22.py} QB21_PFX=r22   # QB22_MPLACE: opt-in (R23 impl/r23/mplace23.py)
export QB_SYN=${QB_SYN:-r10_rpw} QB9_W=${QB9_W:-$B/r10b_ww} QB10_SRD=${QB10_SRD:-0}
export QB9_PER=${QB9_PER:-2.30} QB_TD=${QB_TD:-1} QB_RD=${QB_RD:-0}
export QB_DPL_ARGS=${QB_DPL_ARGS:-"-max_displacement 500"} QB9_CHBLK=${QB9_CHBLK:-40} QB9_GPL2=${QB9_GPL2:-1}
export QB9_GPL2_DENS=${QB9_GPL2_DENS:-0.80} QB_IO_LAT=${QB_IO_LAT:-1.30} QB_RT_LOOPS=${QB_RT_LOOPS:-1}
export QB9_GR_ITER=${QB9_GR_ITER:-10} QB15_GADJ_L=${QB15_GADJ_L-"M5-M9 0.10"} QB_DR_ITER=${QB_DR_ITER:-64}
export QC_PNR_THREADS=${QC_PNR_THREADS:-16}
R21=$root/qc18bacc/impl/r21
SET="QB_GPL_INCR_DENS ${QB_GPL_INCR_DENS:-0.80} PRE_PLACE_TCL $R21/place_pre.tcl PRE_ROUTE_TCL $R21/route_pre.tcl POST_GRT_TCL $R21/post_grt.tcl"
step=${1:?step}; tag=${2:?tag}; d=$B/pnr/$tag
case $step in
gate) echo R22_GATE_START $(date +%T)
     "$root/qc18bacc/impl/r15/run15.sh" fp "$tag" > "$B/pnr/${tag}_fp.out" 2>&1 || { echo R22_FAIL fp; exit 1; }
     grep -h "MPLACE22\|MPLACE15 mid die\|MPLACE9 hub" "$B/pnr/${tag}_fp.out"
     QC_PNR_SET="$SET" QC_PNR_FROM=place QC_PNR_TO=place "$root/flow/tsmc65/pnr/run_pnr.sh" "$root/qc18bacc/impl/r10b/hub.cfg" "$tag" \
         > "$B/pnr/${tag}_place.out" 2>&1
     [ -s "$d/db/place.odb" ] || { echo R22_FAIL place; exit 1; }
     echo R22_PLACED $(date +%T)
     QB_GI=${QB_GI:-10} QB_GTAG=pl "$root/qc18bacc/impl/r15/run15.sh" grt "$tag" place
     echo R22_GRT $(date +%T)
     "$0" bud "$tag"
     python3 -I "$here/gate22.py" "$d/bud_pl" "$d" > "$d/gate22.txt"; cat "$d/gate22.txt"
     echo R22_GATE_DONE $(date +%T) ;;
bud) # budget of the gate GRT; cuts21 S-row regions from this run's floorplan (QB21_SROWS, default = R15 mid rows)
     export QB21_SROWS="$(sed -n 's/^set ::QB15_BANDS {\(.*\)}/\1/p' "$d/mplace.tcl" | tr ' ' '\n' | paste - - - | awk '$1 ~ /^S[0-3]$/ {printf "%s ", $2}')"
     echo R22_SROWS $QB21_SROWS
     "$R21/budget.sh" "$tag" pl place "$d/bud_pl" ;;
sq)  # S-macro net spans of db/place.odb (sq22.tcl -> sq22.py): band H bisection diagnosis (budget item 2)
     ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$d" && QC_FLOW=$FLOW QC_PNR_OUT=$d QB22_OUT=$d/sq22.txt "${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad" -no_init -no_splash -exit \
         "$here/sq22.tcl" > sq22.log 2>&1 < /dev/null )
     python3 -I "$here/sq22.py" "$d/sq22.txt" ;;
prod) echo R22_PROD_START $(date +%T)
     QC_PNR_SET="$SET${QB22_SET_X:+ $QB22_SET_X}" QB_GRT_STOP=1 QC_PNR_FROM=${QB22_FROM:-cts} "$root/flow/tsmc65/pnr/run_pnr.sh" "$root/qc18bacc/impl/r10b/hub.cfg" "$tag"
     [ -s "$d/db/grt.odb" ] || { echo R22_FAIL grt; exit 1; }
     echo R22_PROD_DONE $(date +%T) ;;
dr|post|ant) "$R21/run.sh" "$step" "$tag" ;;
abs) "$R21/run.sh" abs "$tag"; o=$B/r22_$tag
     ( cd "$o" && python3 -I "$root/qc18bacc/impl/r5b/lef_ring.py" qb_hub.lef qb_hub_ring.lef ) && echo R22_RING_LEF ok ;;
fin) "$0" ant "$tag" > "$d/ant_step.out" 2>&1 & "$0" abs "$tag" > "$d/abs_step.out" 2>&1 & "$0" post "$tag"; wait
     cp "$d"/out/etm/qb_hub_{tt,ss,ff}.lib "$d"/out/etm/qb_hub_{tt,ss,ff}_lib.db "$B/r22_$tag/" 2>/dev/null; ls -la "$B/r22_$tag"
     tail -n 3 "$d/ant_step.out" "$d/abs_step.out"; echo R22_FIN_DONE $(date +%T) ;;
*)   sed -n '2,13p' "$0"; exit 1 ;;
esac
