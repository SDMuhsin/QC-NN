#!/usr/bin/env bash
# Column block qb_col_blk (config: blocks/col/col.env + col.cfg; flow/README.md).  On the build host:
#   qc18bacc/flow/blocks/col/run.sh pnr <tag>    floorplan .. place, then CTS .. route .. finish from db/place.odb ($B/pnr/<tag>;
#                                                QC_PNR_FROM / QC_PNR_TO select a step range)
#   qc18bacc/flow/blocks/col/run.sh post <tag>   SPEF tt / ss / ff, PrimeTime tt / ss, abstract LEF + abutment check, ETMs
#                                                tt / ss / ff, LEF-rule antenna check (signoff/antenna.tcl on db/route)
#   qc18bacc/flow/blocks/col/run.sh views <tag>  antenna data in the abstract (out/qb_col_blk_ant.lef), ETM scan (etmcheck 3 ns)
#   qc18bacc/flow/blocks/col/run.sh calibre <tag>  GDS, LVS source, Calibre LVS (lvs_case.sed), DRC (block deck drc_blk.sed),
#                                                antenna -> $B/drc/<tag>  (the top's ring LEF is made by blocks/top/run.sh)
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$here/col.env"
step=${1:?step}; tag=${2:?tag}; d=$B/pnr/$tag
echo "COL_STEP $step $tag $(date +%T)"
case $step in
pnr) mkdir -p "$B/col"; "$PY" -I "$QBF/floorplan/abstract_pins.py" "$COL_REFLEF" "$B/col/colpins.tcl" || exit 1
     export QC_PNR_THREADS=${QC_PNR_THREADS:-15} QB_SYN=$COL_SYN QB_PNR_PERIOD=$COL_PNR_PERIOD QB_RT_LOOPS=0 QB_TILE_DIR=$COL_TILES \
       QB15_GADJ_L=$COL_GADJ_L QB35_COLPINS=$B/col/colpins.tcl QB_IO_LAT=$COL_IO_LAT
     # two sessions as r35_col + r35_colb were built: init .. place, then CTS .. finish restarted from db/place.odb
     to=${QC_PNR_TO:-finish}; from=${QC_PNR_FROM:-init}
     if [ "$from" = init ]; then QC_PNR_TO=place "$ROOT/flow/tsmc65/pnr/run_pnr.sh" "$here/col.cfg" "$tag" || exit 1; from=cts; fi
     [ "$to" = place ] || QC_PNR_FROM=$from QC_PNR_TO=$to "$ROOT/flow/tsmc65/pnr/run_pnr.sh" "$here/col.cfg" "$tag" ;;
post) QC_SPEF_UNESC=1 "$QBF/signoff/spef.sh" "$tag" "tt ss ff"
     qb_kit; . "$d/kit.env"
     ( set -a; . "$(dirname "$NETLIST")/run.env"; set +a
       export QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK= QC_PERIOD=$COL_PT_PERIOD
       cd "$d" || exit 1
       for c in tt ss; do
           QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c qc_tool "pt_blk_$c.log" pt_shell -f "$QBF/signoff/pt/col_blk.tcl"
           echo "PT_BLK $c errors $(grep -c '^Error' pt_blk_$c.log)"; cat "pt_blk_$c.txt"
       done )
     ( cd "$d" && QC_FLOW=$FLOW QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit -log abs.log "$QBF/signoff/etm/col_abs.tcl" > abs.out 2>&1 < /dev/null )
     grep -E "QB5_ANT|QB5_ABUT|ANT-|violat" "$d/abs.log" | tail -5
     echo "ABS_DONE pins $(grep -c '^  PIN' $d/out/$TOP.lef) $(grep -m1 -A0 'SIZE' $d/out/$TOP.lef)"
     ( set -a; . "$(dirname "$NETLIST")/run.env"; set +a
       export QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK= QC_PERIOD=$COL_PT_PERIOD
       cd "$d" || exit 1
       for c in tt ss ff; do
           QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c qc_tool "etm_$c.log" pt_shell -f "$QBF/signoff/etm/etm.tcl"
           echo "ETM $c errors $(grep -c '^Error' etm_$c.log); $(ls out/etm/ 2>/dev/null | tr '\n' ' ')"
       done )
     R29_DB=${R29_DB:-route} R29_TAG=dr "$QBF/common/or.sh" "$tag" "$QBF/signoff/antenna.tcl" r29_antd.log
     grep -hi "R29_ANTD\|found\|violat" "$d/r29_antd.log" | tail -4 ;;
views) LEF=$(. "$d/kit.env"; echo $LEF); o=$d/out
     QB35_AOUT=$o/blkant.txt "$QBF/common/or.sh" "$tag" "$QBF/signoff/etm/blkant.tcl" r35_blkant.log
     "$PY" -I "$QBF/signoff/etm/blkant.py" "$LEF" "$o/blkant.txt" "$o/qb_col_blk.lef" "$o/qb_col_blk_ant.lef" | tail -3
     for c in tt ss ff; do "$PY" -I "$QBF/signoff/etm/etmcheck.py" "$o/etm/qb_col_blk_$c.lib" 3.0; done ;;
calibre) o=$B/drc/$tag; C=$QBF/signoff/calibre; mkdir -p "$o"
     bash "$C/gds.sh" "$tag" "$d/out/qb_col_blk.def" "$o/col.gds" > "$o/gds.log" 2>&1; tail -2 "$o/gds.log"
     bash "$C/lvs_src.sh" "$d/out/qb_col_blk_pg.v" "$o/col_src.spi" > "$o/src.log" 2>&1; tail -3 "$o/src.log"
     QB36_LVS_SED="-f $C/lvs_case.sed" bash "$C/cal.sh" lvs "$o/col.gds" qb_col_blk "$o/col_src.spi" "$o/lvs" > "$o/lvs.log" 2>&1
     QB36_DRC_SED="-f $C/drc_blk.sed" bash "$C/cal.sh" drc "$o/col.gds" qb_col_blk "$o/drcb" > "$o/drcb.log" 2>&1
     bash "$C/cal.sh" ant "$o/col.gds" qb_col_blk "$o/ant" > "$o/ant.log" 2>&1
     cat "$o/lvs.log" "$o/drcb.log" "$o/ant.log" ;;
*) sed -n '2,9p' "$0"; exit 1 ;;
esac
echo "COL_DONE $step $tag $(date +%T)"
