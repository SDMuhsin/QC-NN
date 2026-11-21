#!/usr/bin/env bash
# R40 (results/r40.md): hub sign-off chain on a hold38.sh run, all steps imported (no defaults changed):
#   1. impl/r38/fin38.sh hub <tag>  (SPEF, fin, antd29, pt37 tt/ss with R37 conditions, antenna LEF, ring LEF, etmcheck)
#      cfg / r34_L.txt from QB38_HUBSRC (default here r38_hub_rr)
#   2. GDS (impl/r38/gds38.sh, SRAM abstracts as R38), LVS source (lvssrc38.sh + SRAM stubs), Calibre LVS (impl/r36/cal36.sh,
#      lvs_hub.sed + lvs_hubpg.sed as R38) and Calibre antenna.   fin40.sh <tag> [skipfin]
set -u
here=$(cd "$(dirname "$0")" && pwd); I=$(cd "$here/.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
tag=${1:?tag}; d=$B/pnr/$tag; o=$B/drc/$tag; R38=${QB40_R38DRC:-$B/drc/r38_hub}; mkdir -p "$o"
ts() { echo "FIN40 $tag $1 $(date -u +%T)"; }
[ "${2:-}" = skipfin ] || { ts fin38; QB38_HUBSRC=${QB38_HUBSRC:-r38_hub_rr} bash "$I/r38/fin38.sh" hub "$tag"; }
ts gds; ML=$(cd "$d" && . ./kit.env && echo "$MACRO_LEFS")
QB38_GDS_EXTRA=$R38/sram_abs.gds bash "$I/r38/gds38.sh" "$tag" "$d/out/qb_hub.def" "$o/hub.gds" $ML > "$o/gds.log" 2>&1; tail -2 "$o/gds.log"
ts lvssrc; bash "$I/r38/lvssrc38.sh" "$d/out/qb_hub_pg.v" "$o/hub_src.spi" "$R38/sram_stub.spi" > "$o/lvssrc.log" 2>&1; tail -3 "$o/lvssrc.log"
ts lvs_ant
QB36_LVS_SED="-f $I/r38/lvs_hub.sed -f $I/r38/lvs_hubpg.sed" bash "$I/r36/cal36.sh" lvs "$o/hub.gds" qb_hub "$o/hub_src.spi" "$o/lvs" > "$o/lvs.log" 2>&1 &
QB36_DRC_SED="-f $I/r38/drc_xsram.sed" bash "$I/r36/cal36.sh" ant "$o/hub.gds" qb_hub "$o/ant" > "$o/ant.log" 2>&1 &
wait; cat "$o/lvs.log" "$o/ant.log"
ts done
