#!/usr/bin/env bash
# Column block qb_col_blk (config: blocks/col/col.env + icc2.cfg; flow/README.md).  On the build host:
#   qc18bacc/flow/blocks/col/run.sh pnr <tag>      ICC2 (flow/icc2): libs init floorplan place cts route outputs in
#                                                  $B/icc2/col/<tag> (QC_PNR_FROM / QC_PNR_TO select a step range)
#   qc18bacc/flow/blocks/col/run.sh post <tag>     PrimeTime tt / ss / ff on the ICC2 netlist + SPEF, ETMs tt / ss / ff
#   qc18bacc/flow/blocks/col/run.sh calibre <tag>  LVS source, Calibre LVS (lvs_case.sed), DRC (block deck drc_blk.sed),
#                                                  antenna on the ICC2 GDS -> <run>/calibre
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$here/col.env"
step=${1:?step}; tag=${2:?tag}; d=$B/icc2/col/$tag
export QB_SYN=$COL_SYN QB_PNR_PERIOD=$COL_PNR_PERIOD COL_TOP COL_PIN_DEF QB_ICC2_CFG=$here/icc2.cfg
echo "COL_STEP $step $tag $(date +%T)"
case $step in
pnr) on=0
     for s in libs init floorplan place cts route outputs; do
         [ "$s" = "${QC_PNR_FROM:-libs}" ] && on=1; [ $on = 1 ] || continue
         qb_icc2 "$d" $s "$([ $s = libs ] && echo icc2_lm_shell)" || exit 1
         [ "$s" = "${QC_PNR_TO:-outputs}" ] && break
     done
     cat "$d/summary.txt" | tail -40 ;;
post) qb_kit
     ( set -a; . "$B/syn/$COL_SYN/run.env"; set +a
       export QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK= QC_PERIOD=$COL_PT_PERIOD
       cd "$d" || exit 1
       for c in tt ss ff; do
           QC_PNR_OUT=$d QC_TOP=$COL_TOP QC_CORNER=$c qb_pt "pt_blk_$c.log" pt_shell -f "$QBF/signoff/pt/col_blk.tcl" || exit 1
           cat "pt_blk_$c.txt"
       done
       for c in tt ss ff; do
           QC_PNR_OUT=$d QC_TOP=$COL_TOP QC_CORNER=$c qb_pt "etm_$c.log" pt_shell -f "$QBF/signoff/etm/etm.tcl" || exit 1
           echo "ETM $c $(ls out/etm/ 2>/dev/null | tr '\n' ' ')"
       done ) || exit 1 ;;
calibre) o=$d/calibre; C=$QBF/signoff/calibre; mkdir -p "$o"
     bash "$C/lvs_src.sh" "$d/out/${COL_TOP}_pg.v" "$o/col_src.spi" > "$o/src.log" 2>&1; r=$?; tail -3 "$o/src.log"; [ $r = 0 ] || exit 1
     r=0
     QB36_LVS_SED="-f $C/lvs_case.sed" bash "$C/cal.sh" lvs "$d/out/$COL_TOP.gds" "$COL_TOP" "$o/col_src.spi" "$o/lvs" > "$o/lvs.log" 2>&1 || r=1
     QB36_DRC_SED="-f $C/drc_blk.sed" bash "$C/cal.sh" drc "$d/out/$COL_TOP.gds" "$COL_TOP" "$o/drcb" > "$o/drcb.log" 2>&1 || r=1
     bash "$C/cal.sh" ant "$d/out/$COL_TOP.gds" "$COL_TOP" "$o/ant" > "$o/ant.log" 2>&1 || r=1
     cat "$o/lvs.log" "$o/drcb.log" "$o/ant.log"; [ $r = 0 ] || exit 1 ;;
*) sed -n '2,7p' "$0"; exit 1 ;;
esac
echo "COL_DONE $step $tag $(date +%T)"
