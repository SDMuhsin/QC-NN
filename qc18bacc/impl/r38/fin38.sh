#!/usr/bin/env bash
# R38: re-sign-off of a re-routed block copy (reroute38.tcl) with R37's recipes (results/r37.md), steps imported:
#   fin38.sh act <tag>   SPEF tt/ss/ff + PT tt/ss 6.5 ns (QB7_AOUT 0.25, QB7_DIN 0.74), LEF-rule antenna (finish db),
#                        abstract + ETMs tt/ss/ff ($B/r9a_blk/<tag>), antenna data in the LEF, ring LEF, etmcheck
#   fin38.sh hub <tag>   cfg dir $QB9_W/cfg_<tag> (copy of cfg_<QB38_HUBSRC [r35_hubC]>), r34_L.txt copied, SPEF tt, run34 fin
#                        (abs / ant / post: SPEF ss ff, PT + ETMs), antenna (finish db), pt37 tt/ss (R37 conditions),
#                        antenna data, ring LEF, etmcheck ($B/r22_<tag>)
set -u
here=$(cd "$(dirname "$0")" && pwd); S=$(cd "$here/../../.." && pwd); I=$S/qc18bacc/impl
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD; P=$B/pnr; PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3
blk=${1:?act|hub}; tag=${2:?tag}; d=$P/$tag; cd "$S" || exit 1
ts() { echo "FIN38 $blk $tag $1 $(date -u +%T)"; }
case $blk in
act) o=$B/r9a_blk/$tag
  ts post; QC_SPEF_UNESC=1 QB_SYN=r35_act QB_PT_PERIOD=6.5 QB_PT_CORNERS="tt ss" QB7_AOUT=0.25 QB7_DIN=0.74 bash "$I/r20/run.sh" post "$tag"
  ts antd; R29_DB=finish R29_TAG=fin bash "$I/r29/or29.sh" "$tag" "$I/r29/antd29.tcl" r29_antd.log; grep -h "Found\|R29_ANTD" "$d/r29_antd.log" | tail -3
  ts abs; QB7_AOUT=0.25 QB7_DIN=0.74 bash "$I/r35/run35.sh" actabs "$tag" 6.5 | tail -3
  ts blkant; QB35_AOUT=$o/blkant.txt QB35_ADB=finish bash "$I/r29/or29.sh" "$tag" "$I/r35/blkant.tcl" r38_blkant.log
  LEF=$(. "$d/kit.env"; echo $LEF); "$PY" -I "$I/r35/blkant.py" "$LEF" "$o/blkant.txt" "$o/qb_act2_blk.lef" "$o/qb_act2_blk_ant.lef" | tail -3
  "$PY" -I "$I/r5b/lef_ring.py" "$o/qb_act2_blk_ant.lef" "$o/qb_act2_blk_ant_ring.lef" | tail -2
  for c in tt ss ff; do "$PY" -I "$I/r35/etmcheck.py" "$o/qb_act2_blk_$c.lib" 3.0; done ;;
hub) o=$B/r22_$tag; W=${QB9_W:-$B/r26_w}; src=${QB38_HUBSRC:-r35_hubC}
  mkdir -p "$W/cfg_$tag"; for f in "$W/cfg_$src"/*; do sed "s#cfg_$src#cfg_$tag#g" "$f" > "$W/cfg_$tag/$(basename "$f")"; done
  sed -i "s#cfg_$src#cfg_$tag#g; s#/pnr/$src\b#/pnr/$tag#g" "$d/kit.env"; cp "$P/$src/r34_L.txt" "$d/"
  for f in mplace.tcl macros.txt pins9_data.tcl; do [ -f "$P/$src/$f" ] && cp "$P/$src/$f" "$d/"; done
  ts spef_tt; QC_SPEF_UNESC=1 QB_SPEF_CORNERS=tt bash "$I/pnr/run.sh" spef "$tag"
  ts fin; bash "$I/r34/run34.sh" fin "$tag" 6.5 > "$d/r38_fin.out" 2>&1; tail -4 "$d/r38_fin.out"
  ts antd_pt; R29_DB=finish R29_TAG=fin bash "$I/r29/or29.sh" "$tag" "$I/r29/antd29.tcl" r29_antd.log &
  for c in tt ss; do QB_PT_PERIOD=6.5 QB37_LAT=p50 QB37_FT=1 QB37_VIOL=1 QB37_FR="actout 0.26" bash "$I/r37/pt37.sh" "$tag" $c > "$d/r38_pt_$c.out" 2>&1 & done; wait
  grep -h "Found\|R29_ANTD" "$d/r29_antd.log" | tail -3; for c in tt ss; do grep "^R37\|violating\|slack_ns" "$d/r38_pt_$c.out" | cut -c1-200; done
  ts blkant; QB35_AOUT=$o/blkant.txt QB35_ADB=finish bash "$I/r29/or29.sh" "$tag" "$I/r35/blkant.tcl" r38_blkant.log
  LEF=$(. "$d/kit.env"; echo $LEF); "$PY" -I "$I/r35/blkant.py" "$LEF" "$o/blkant.txt" "$o/qb_hub.lef" "$o/qb_hub_ant.lef" | tail -3
  "$PY" -I "$I/r5b/lef_ring.py" "$o/qb_hub_ant.lef" "$o/qb_hub_ant_ring.lef" | tail -2
  for c in tt ss ff; do "$PY" -I "$I/r35/etmcheck.py" "$o/qb_hub_$c.lib" 3.0; done ;;
esac
ts done
