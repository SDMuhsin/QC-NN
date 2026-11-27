#!/usr/bin/env bash
# Act block qb_act2_blk (config: blocks/act/act.env + act.cfg; flow/README.md).  On the build host ($B/pnr/<tag>):
#   qc18bacc/flow/blocks/act/run.sh pnr <tag>            floorplan .. place .. CTS, stop (db/cts.odb; QC_PNR_TO [cts])
#   qc18bacc/flow/blocks/act/run.sh postcts <src> <tag>  <src>'s db/cts.odb -> re-spread + post-CTS repair -> db/cts_rt.odb
#   qc18bacc/flow/blocks/act/run.sh route <src> <tag>    <src>'s db/cts_rt.odb -> GRT, antenna repair, DR, finish (route/act_route.tcl)
#   qc18bacc/flow/blocks/act/run.sh drveco <tag>         PrimeTime DRV ECO ss + tt (signoff/pt/drv_eco.tcl) -> out/drv_eco_tt.tcl
#   qc18bacc/flow/blocks/act/run.sh hold <tag> [margin]  PT DRV ECO file (if any) + DRV / hold repair at tt + ss, full re-route
#                                                        (repair/hold_eco.sh, margin ACT_HOLD_M)
#   qc18bacc/flow/blocks/act/run.sh post <tag>           SPEF tt / ss / ff, PT tt / ss / ff, DRC histogram, LEF-rule antenna (finish db),
#                                                        abstract + abutment check + ETMs tt / ss / ff, antenna data in the LEF,
#                                                        ring LEFs, etmcheck -> $B/r9a_blk/<tag>
#   qc18bacc/flow/blocks/act/run.sh calibre <tag>        GDS, LVS source, Calibre LVS (lvs_case.sed), DRC (drc_blk.sed), antenna
#                                                        -> $B/drc/<tag>
# Production (R50): pnr r48_act_p; postcts r48_act_p r48_act_s; route r48_act_s r48_act; post; hold; post; calibre
# (results/r48.md, r49.md, r50.md).  The R37 / R38 lineage steps (eco1, eco6, reroute: r35_act_c -> r38_act_rr2) were
# removed in R50; they are in git history (results/r37.md, r38.md).
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$here/act.env"
step=${1:?step}; tag=${2:?tag}
# design environment of every OpenROAD process that re-sources the run's config (run_pnr.sh, common/or.sh, hold_eco.sh)
export QB_SYN=$ACT_SYN QB_PNR_PERIOD=$ACT_PNR_PERIOD QB7_COLPINS=$ACT_COLPINS QB7_YOFF=$ACT_YOFF QB7_MAXTRAN=$ACT_MAXTRAN \
  QB7_MAXFO=$ACT_MAXFO QB7_DPL_ARGS=$ACT_DPL QB_DRV_SLEW=$ACT_MAXTRAN QB15_GADJ_L=$ACT_GADJ_L
echo "ACT_STEP $* $(date +%T)"
case $step in
pnr) d=$B/pnr/$tag
     QC_PNR_TO=${QC_PNR_TO:-cts} QC_PNR_THREADS=${QC_PNR_THREADS:-16} \
       /usr/bin/time -v -o "$B/pnr_$tag.time" "$ROOT/flow/tsmc65/pnr/run_pnr.sh" "$here/act.cfg" "$tag" || exit 1 ;;
postcts) src=$B/pnr/$tag; tag=${3:?tag}; d=$B/pnr/$tag; per=$ACT_PNR_PERIOD
     rm -rf "$d"; mkdir -p "$d/db" "$d/rpt"
     cd "$src" && cp -r kit.env rc "$d/" && cp db/cts.odb "$d/db/" && grep -v postcts summary.txt > "$d/summary.txt"
     half=$(awk -v p=$per 'BEGIN{print p/2}')
     sed -E "s/(create_clock .*-period )[0-9.]+/\\1$per/; s/-waveform \\{0 [0-9.]+\\}/-waveform {0 $half}/" db/cts.sdc > "$d/db/cts.sdc"
     QC_PNR_FROM=route QC_PNR_THREADS=${QC_PNR_THREADS:-16} QB_RT_LOOPS=$ACT_RT_LOOPS \
       /usr/bin/time -v -o "$B/pnr_$tag.time" "$ROOT/flow/tsmc65/pnr/run_pnr.sh" "$here/act.cfg" "$tag"
     ls -la "$d/db/cts_rt.odb" || exit 1 ;;
route) src=$B/pnr/$tag; tag=${3:?tag}; d=$B/pnr/$tag
     rm -rf "$d"; mkdir -p "$d/db" "$d/rpt"; cp "$src/config.tcl" "$src/kit.env" "$src/summary.txt" "$d/"
     cp -r "$src/rc" "$d/"; cp "$src/db/cts_rt.odb" "$src/db/cts.sdc" "$d/db/"
     ( qb_kit; cd "$d" && QC_FLOW=$FLOW QC_PNR_OUT=$d QC_PNR_THREADS=${QC_PNR_THREADS:-14} \
       /usr/bin/time -v -o route.time "$OR" -no_init -no_splash -exit -log openroad.log "$QBF/route/act_route.tcl" > openroad.out 2>&1 < /dev/null )
     echo "ROUTE rc $?" ;;
hold) d=$B/pnr/$tag
     [ -e "$d/db/route_dr.odb" ] || touch "$d/db/route_dr.odb"     # hold_eco.tcl copies route_dr -> route_dr_prehold before its save
     QB35_HDB=finish QB35_PER=$ACT_PT_PERIOD QB35_HOLD_M=${3:-$ACT_HOLD_M} QB35_FILL_BEFORE=1 \
       QB37_FORCE_SAVE=1 QB35_THREADS=${QB35_THREADS:-14} QB37_HPRE_TCL= QB37_HPOST_TCL= QB35_IO_TCL=$QBF/repair/block_io.tcl \
       QB35_IOL= QB7_DPL_ARGS= QB7_AOUT=$ACT_AOUT QB7_DIN=$ACT_DIN QB35_ECO_TCL=$([ -f "$d/out/drv_eco_tt.tcl" ] && echo "$d/out/drv_eco_tt.tcl") \
       "$QBF/repair/hold_eco.sh" "$tag"
     rm -f "$d/db/route_dr_prehold.odb" ;;
post) d=$B/pnr/$tag; o=$B/r9a_blk/$tag; mkdir -p "$o"
     ts() { echo "ACT_POST $tag $1 $(date -u +%T)"; }
     ts post
     ( export QC_SPEF_UNESC=1 QB7_AOUT=$ACT_AOUT QB7_DIN=$ACT_DIN
       "$QBF/signoff/spef.sh" "$tag" "tt ss ff"
       ( . "$ROOT/flow/tsmc65/common/tool.sh"; . "$d/kit.env"; set -a; . "$(dirname "$NETLIST")/run.env"; set +a
         export QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK= QC_PERIOD=$ACT_PT_PERIOD
         cd "$d" || exit 1
         for c in tt ss ff; do
             QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c qb_pt "pt_blk_$c.log" pt_shell -f "$QBF/signoff/pt/act_blk.tcl" || exit 1
             cat "pt_blk_$c.txt"
         done ) || exit 1
       [ -f "$d/rpt/drt.drc.rpt" ] && "$PY" -I "$QBF/signoff/drc_hist.py" "$d/rpt/drt.drc.rpt" > "$d/drc_hist.txt" )
     ts antd; R29_DB=finish R29_TAG=fin "$QBF/common/or.sh" "$tag" "$QBF/signoff/antenna.tcl" r29_antd.log
     grep -h "Found\|R29_ANTD" "$d/r29_antd.log" | tail -3
     ts abs
     ( export QB7_AOUT=$ACT_AOUT QB7_DIN=$ACT_DIN
       ( qb_kit; cd "$d" && QC_FLOW=$FLOW QC_PNR_OUT=$d QB9_ABS_OUT=$o \
         "$OR" -no_init -no_splash -exit -log abs.log "$QBF/signoff/etm/act_abs.tcl" > abs.out 2>&1 < /dev/null )
       grep "QB9_" "$d/abs.log"
       "$PY" -I "$QBF/signoff/etm/lef_size.py" "$o/qb_act2_blk.lef" "$d/abs.log" && \
         ( cd "$o" && "$PY" -I "$QBF/signoff/etm/lef_ring.py" qb_act2_blk.lef qb_act2_blk_ring.lef )
       ( . "$ROOT/flow/tsmc65/common/tool.sh"; . "$d/kit.env"; set -a; . "$(dirname "$NETLIST")/run.env"; set +a
         export QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK= QC_PERIOD=$ACT_PT_PERIOD
         cd "$d" || exit 1
         for c in tt ss ff; do      # serial: parallel extract_model runs share the temp file ./<top>_lib.lib in the run dir
             QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c qb_pt "etm_$c.log" pt_shell -f "$QBF/signoff/etm/etm.tcl" || exit 1
         done ) || exit 1
       cp "$d/out/qb_act2_blk.v" "$d"/out/etm/qb_act2_blk_{tt,ss,ff}{.lib,_ref.txt,_lib.db} "$o/"
       ls -la "$o" ) | tail -3
     ts blkant; QB35_AOUT=$o/blkant.txt QB35_ADB=finish "$QBF/common/or.sh" "$tag" "$QBF/signoff/etm/blkant.tcl" r38_blkant.log
     LEF=$(. "$d/kit.env"; echo $LEF); "$PY" -I "$QBF/signoff/etm/blkant.py" "$LEF" "$o/blkant.txt" "$o/qb_act2_blk.lef" "$o/qb_act2_blk_ant.lef" | tail -3
     "$PY" -I "$QBF/signoff/etm/lef_ring.py" "$o/qb_act2_blk_ant.lef" "$o/qb_act2_blk_ant_ring.lef" | tail -2
     for c in tt ss ff; do "$PY" -I "$QBF/signoff/etm/etmcheck.py" "$o/qb_act2_blk_$c.lib"; done ;;
drveco) d=$B/pnr/$tag   # PrimeTime DRV ECO (signoff/pt/drv_eco.tcl): ss, then tt on top (out/drv_eco_tt.tcl = both)
     ( . "$ROOT/flow/tsmc65/common/tool.sh"; . "$d/kit.env"; set -a; . "$(dirname "$NETLIST")/run.env"; set +a
       export QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK= QC_PERIOD=$ACT_PT_PERIOD QB_PT_SCRIPT=$QBF/signoff/pt/act_blk.tcl \
         QB7_AOUT=$ACT_AOUT QB7_DIN=$ACT_DIN
       for c in ss tt; do mkdir -p "$d/w_eco_$c"; cd "$d/w_eco_$c" || exit 1
           QB_PT_PRE_ECO=$([ $c = tt ] && echo "$d/out/drv_eco_ss.tcl") QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c \
             qb_pt "$d/drv_eco_$c.log" pt_shell -f "$QBF/signoff/pt/drv_eco.tcl" || exit 1
           grep "^drv\|QB_DRV_ECO" "$d/drv_eco_$c.log"
       done ) || exit 1 ;;
calibre) d=$B/pnr/$tag; o=$B/drc/$tag; C=$QBF/signoff/calibre; mkdir -p "$o"
     bash "$C/gds.sh" "$tag" "$d/out/qb_act2_blk.def" "$o/act.gds" > "$o/gds.log" 2>&1; r=$?; tail -2 "$o/gds.log"; [ $r = 0 ] || exit 1
     bash "$C/lvs_src.sh" "$d/out/qb_act2_blk_pg.v" "$o/act_src.spi" > "$o/src.log" 2>&1; r=$?; tail -3 "$o/src.log"; [ $r = 0 ] || exit 1
     r=0
     QB36_LVS_SED="-f $C/lvs_case.sed" bash "$C/cal.sh" lvs "$o/act.gds" qb_act2_blk "$o/act_src.spi" "$o/lvs" > "$o/lvs.log" 2>&1 || r=1
     QB36_DRC_SED="-f $C/drc_blk.sed" bash "$C/cal.sh" drc "$o/act.gds" qb_act2_blk "$o/drcb" > "$o/drcb.log" 2>&1 || r=1
     bash "$C/cal.sh" ant "$o/act.gds" qb_act2_blk "$o/ant" > "$o/ant.log" 2>&1 || r=1
     cat "$o/lvs.log" "$o/drcb.log" "$o/ant.log"; [ $r = 0 ] || exit 1 ;;
*) sed -n '2,20p' "$0"; exit 1 ;;
esac
echo "ACT_DONE $* $(date +%T)"
