#!/usr/bin/env bash
# R31 (results/r31.md): hub qb_hub at the original die (QB_SB 649, 3990 x 1950.8, floorplan pn2) with every fix so far,
# end to end.  On tau from the snapshot root:
#   qc18bacc/impl/r31/run31.sh all <tag> <period>
#   qc18bacc/impl/r31/run31.sh mk <tag> <period> <src>; from <tag> <period>   new run from <src>'s placement, prod .. pt
#   qc18bacc/impl/r31/run31.sh redo <tag> <period>   dio .. pt again on db/grt.odb (antenna round 2: R31_SEED, R29_HPWL; R31_PDN="" as the db is trimmed)
# = impl/r28/run28.sh gate, prod, meas (r26_p1 settings, RTL QB_TOP_PTR=1 netlist r26_ptr, gpl density 0.65) ->
#   impl/r29/run29.sh dio (diodes R29_SHPWL 1500, macro-PDN trim pdn29.tcl, LEF-rule GR check) -> dr -> fin ->
#   impl/r29/antd29.tcl (LEF-rule antenna on route_dr) -> impl/r31/pt31.sh tt, ss.
# Fixes (all opt-in env): QB15_GADJ_L "M5-M9 0.10 M2-M3 0.6" (R30), QB31_SDC 1 (impl/r9b/sdc.py EMA regexp),
# QC_SPEF_UNESC 1 (flow def2spef.py: unescaped conn names in the PrimeTime SPEF).
set -u
here=$(cd "$(dirname "$0")" && pwd); I=$(cd "$here/.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
step=${1:?step}; tag=${2:?tag}; per=${3:?period}
if [ "$step" = mk ]; then   # mk <tag> <period> <src>: new run <tag> from <src>'s placement (db/place, init; cfg dir renamed)
  s=$B/pnr/${4:?src}; d=$B/pnr/$tag; W=${QB9_W:-$B/r26_w}; mkdir -p "$d/db" "$d/rpt" "$d/out" "$W/cfg_$tag"
  for f in config.tcl kit.env mplace.tcl macros.txt pins9_data.tcl; do cp "$s/$f" "$d/"; done; cp -r "$s/rc" "$d/"
  for f in init place; do cp "$s/db/$f.odb" "$s/db/$f.sdc" "$d/db/"; done
  for f in "$W/cfg_$4"/*; do sed "s#cfg_$4#cfg_$tag#g" "$f" > "$W/cfg_$tag/$(basename "$f")"; done
  sed -i "s#cfg_$4#cfg_$tag#g; s#/pnr/$4\b#/pnr/$tag#g" "$d/kit.env"; grep -h "cfg_\|$4" "$d/kit.env" | cut -c1-160; exit 0
fi
export QB9_PER=$per QB_PT_PERIOD=$per QB15_GADJ_L=${QB15_GADJ_L-"M5-M9 0.10 M2-M3 0.6"} QB31_SDC=${QB31_SDC:-1} QC_SPEF_UNESC=${QC_SPEF_UNESC:-1}
export QB_SB=${QB_SB:-649}
ts() { echo "R31_STEP $1 $tag $(date +%T)"; }
case $step in
all) for s in gate prod meas dio dr fin antd pt; do "$0" $s "$tag" "$per" || { echo "R31_FAIL $s"; exit 1; }; done ;;
from) for s in prod meas dio dr fin antd pt; do "$0" $s "$tag" "$per" || { echo "R31_FAIL $s"; exit 1; }; done ;;   # after mk
redo) for s in dio dr fin antd pt; do "$0" $s "$tag" "$per" || { echo "R31_FAIL $s"; exit 1; }; done ;;   # after seed31.sh: R31_SEED=<run>/r31_seed.txt
gate|prod|meas|dr|fin) ts $step; "$I/r28/run28.sh" $step "$tag" ;;
dio) ts dio; R29_DIO_PFX=${R29_DIO_PFX:-r29_dio_} R29_SEED=${R31_SEED-} R29_HPWL=${R29_HPWL:-0} R29_SHPWL=${R29_SHPWL:-1500} R29_PDN=${R31_PDN-$I/r29/pdn29.tcl} R29_ANTD=1 "$I/r29/run29.sh" dio "$tag"; grep -q "R29_DIO done" "$B/pnr/$tag/r29_dio.log" || { echo R31_DIO_FAILED; exit 1; } ;;
antd) ts antd; R29_DB=route_dr R29_TAG=dr "$I/r29/or29.sh" "$tag" "$I/r29/antd29.tcl" r29_antd.log; grep -hi "R29_ANTD\|found\|violat" "$B/pnr/$tag/r29_antd.log" | tail -4 ;;
pt) ts pt; "$here/pt31.sh" "$tag" tt & "$here/pt31.sh" "$tag" ss; wait ;;
*) sed -n 2,9p "$0"; exit 1 ;;
esac
ts done_$step
