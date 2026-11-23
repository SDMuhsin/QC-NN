#!/usr/bin/env bash
# Column block qb_col_blk (config: blocks/col/col.env + icc2.cfg; flow/README.md).  On the build host:
#   qc18bacc/flow/blocks/col/run.sh pnr <tag>      ICC2 (flow/icc2): libs init floorplan place cts route outputs in
#                                                  $B/icc2/col/<tag> (QC_PNR_FROM / QC_PNR_TO select a step range)
#   qc18bacc/flow/blocks/col/run.sh eco <tag>      one sign-off ECO round on the routed run: PrimeTime DMSA tt / ss / ff
#                                                  (signoff/pt/drv_eco.tcl: DRV, then hold) -> out/eco/pt_eco.tcl, applied by
#                                                  ICC2 (flow/icc2/eco.tcl: label route -> eco), outputs of label eco
#   qc18bacc/flow/blocks/col/run.sh post <tag>     PrimeTime tt / ss / ff on the ICC2 netlist + SPEF, ETMs tt / ss / ff
#   qc18bacc/flow/blocks/col/run.sh views <tag>    views for the chip top (blocks/top/run.sh views reads them): ICC2
#                                                  abstract LEF + port antenna data + abutment check (flow/icc2/abstract.tcl,
#                                                  label QB_ICC2_LABEL [eco]) -> out/<top>_ant.lef; ETM scan (etmcheck 3 ns)
#                                                  of the post step's out/etm/<top>_<c>.lib
#   qc18bacc/flow/blocks/col/run.sh calibre <tag>  kit dummy metal fill (fill_blk.sed) on the ICC2 GDS, then on the
#                                                  filled GDS: LVS source, Calibre LVS (lvs_case.sed), DRC (block deck
#                                                  drc_blk.sed), antenna -> <run>/calibre
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$here/col.env"
step=${1:?step}; tag=${2:?tag}; d=$B/icc2/col/$tag
export QB_SYN=$COL_SYN QB_PNR_PERIOD=$COL_PNR_PERIOD COL_TOP COL_PIN_DEF QB_ICC2_CFG=$here/icc2.cfg
echo "COL_STEP $step $tag $(date +%T)"
pt_env() {   # PrimeTime environment of the block sign-off script (signoff/pt/col_blk.tcl), run in the subshell of the caller
    qb_kit; set -a; . "$B/syn/$COL_SYN/run.env"; set +a
    export QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK= QC_PERIOD=$COL_PT_PERIOD QC_PNR_OUT=$d QC_TOP=$COL_TOP
    cd "$d"
}
case $step in
pnr) on=0
     for s in libs init floorplan place cts route outputs; do
         [ "$s" = "${QC_PNR_FROM:-libs}" ] && on=1; [ $on = 1 ] || continue
         qb_icc2 "$d" $s "$([ $s = libs ] && echo icc2_lm_shell)" || exit 1
         [ "$s" = "${QC_PNR_TO:-outputs}" ] && break
     done
     cat "$d/summary.txt" | tail -40 ;;
eco) ( pt_env || exit 1
       QB_PT_SCRIPT=$QBF/signoff/pt/col_blk.tcl QB_ECO_CORNERS="tt ss ff" QB_ECO_NLIB=$d/$COL_TOP.nlib QB_ECO_BLOCK=$COL_TOP/route \
           qb_pt pt_eco.log pt_shell -multi_scenario -f "$QBF/signoff/pt/drv_eco.tcl" ) || exit 1
     cat "$d/out/eco/eco_summary.txt"
     qb_icc2 "$d" eco || exit 1
     QB_ICC2_LABEL=eco qb_icc2 "$d" outputs || exit 1
     grep '^eco' "$d/summary.txt" | tail -20 ;;
post) ( pt_env || exit 1
       for c in tt ss ff; do
           QC_CORNER=$c qb_pt "pt_blk_$c.log" pt_shell -f "$QBF/signoff/pt/col_blk.tcl" || exit 1
           cat "pt_blk_$c.txt"
       done
       for c in tt ss ff; do
           QC_CORNER=$c qb_pt "etm_$c.log" pt_shell -f "$QBF/signoff/etm/etm.tcl" || exit 1
           echo "ETM $c $(ls out/etm/ 2>/dev/null | tr '\n' ' ')"
       done ) || exit 1 ;;
views) QB_ICC2_LABEL=${QB_ICC2_LABEL:-eco} QB_PY=$PY qb_icc2 "$d" abstract || exit 1
     grep '^abstract' "$d/summary.txt" | tail -3
     for c in tt ss ff; do "$PY" -I "$QBF/signoff/etm/etmcheck.py" "$d/out/etm/${COL_TOP}_$c.lib" 3.0 || exit 1; done ;;
calibre) o=$d/calibre; C=$QBF/signoff/calibre; mkdir -p "$o"
     QB55_FILL_SED="-f $C/fill_blk.sed" bash "$C/cal.sh" fill "$d/out/$COL_TOP.gds" "$COL_TOP" "$o/fill" > "$o/fill.log" 2>&1 \
         || { cat "$o/fill.log"; exit 1; }
     cat "$o/fill.log"; g=$o/fill/${COL_TOP}_fill.gds
     bash "$C/lvs_src.sh" "$d/out/${COL_TOP}_pg.v" "$o/col_src.spi" > "$o/src.log" 2>&1; r=$?; tail -3 "$o/src.log"; [ $r = 0 ] || exit 1
     r=0
     QB36_LVS_SED="-f $C/lvs_case.sed" bash "$C/cal.sh" lvs "$g" "$COL_TOP" "$o/col_src.spi" "$o/lvs" > "$o/lvs.log" 2>&1 || r=1
     QB36_DRC_SED="-f $C/drc_blk.sed" bash "$C/cal.sh" drc "$g" "$COL_TOP" "$o/drcb" > "$o/drcb.log" 2>&1 || r=1
     bash "$C/cal.sh" ant "$g" "$COL_TOP" "$o/ant" > "$o/ant.log" 2>&1 || r=1
     cat "$o/lvs.log" "$o/drcb.log" "$o/ant.log"; [ $r = 0 ] || exit 1 ;;
*) sed -n '2,15p' "$0"; exit 1 ;;
esac
echo "COL_DONE $step $tag $(date +%T)"
