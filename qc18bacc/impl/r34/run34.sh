#!/usr/bin/env bash
# R34 (results/r34.md): hub qb_hub, original die (QB_SB 649, 3990 x 1950.8), with every R29-R33 fix through the one
# preset impl/r34/preset.env.  On tau from the snapshot root:
#   qc18bacc/impl/r34/run34.sh all <tag> <period>    gate prod meas dio dr fin antd pt   (from: without gate; resume: rt instead of gate prod)
#   qc18bacc/impl/r34/run34.sh <step> <tag> <period> one step of impl/r31/run31.sh (gate prod meas dio dr fin antd pt redo)
# After prod, QB_IO_LAT = <run>/r34_L.txt (L measured by route_pre.tcl on the run's cts db) for every later step.
set -u
export R34=$(cd "$(dirname "$0")" && pwd); I=$(cd "$R34/.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
step=${1:?step}; tag=${2:?tag}; per=${3:?period}; d=$B/pnr/$tag
. "$R34/preset.env"
case $step in   # all = gate .. pt; from = prod .. pt (after a gate); resume = rt .. pt (after a prod that saved db/cts_rt)
all|from|resume) ss="meas dio dr fin antd pt"; [ "$step" = resume ] && ss="rt $ss" || ss="prod $ss"; [ "$step" = all ] && ss="gate $ss"
  for s in $ss; do "$0" $s "$tag" "$per" || { echo "R34_FAIL $s"; exit 1; }; done; exit 0 ;;
rt) # the route step again from db/cts_rt (post-CTS repair kept: QB_POSTCTS 0; its IO delays are in cts_rt.sdc):
    # cts_rt stands in for cts as the route step's input, cts.odb is restored afterwards
  [ -s "$d/db/cts_rt.odb" ] && [ -s "$d/r34_L.txt" ] || { echo "R34_FAIL rt: no cts_rt / r34_L.txt"; exit 1; }
  rm -f "$d/db/grt.odb"; for e in odb sdc; do cp "$d/db/cts.$e" "$d/db/cts_orig.$e" && cp "$d/db/cts_rt.$e" "$d/db/cts.$e"; done
  export QB_IO_LAT=$(cat "$d/r34_L.txt"); echo "R34_STEP rt $tag $per QB_IO_LAT $QB_IO_LAT $(date +%T)"
  QB9_PER=$per QB_PT_PERIOD=$per QB_POSTCTS=0 QB34_LAT=0 QB22_FROM=route "$I/r28/run28.sh" prod "$tag"; rc=$?
  for e in odb sdc; do mv "$d/db/cts_orig.$e" "$d/db/cts.$e"; done
  [ -s "$d/db/grt.odb" ] || exit 1; exit $rc ;;
esac
if [ "$step" != gate ] && [ "$step" != prod ]; then
  [ -s "$d/r34_L.txt" ] || { echo "R34_FAIL no $d/r34_L.txt"; exit 1; }
  export QB_IO_LAT=$(cat "$d/r34_L.txt")
fi
echo "R34_STEP $step $tag $per QB_IO_LAT ${QB_IO_LAT:-measured} $(date +%T)"
"$I/r31/run31.sh" "$step" "$tag" "$per"
