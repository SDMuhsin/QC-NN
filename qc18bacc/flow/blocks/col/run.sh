#!/usr/bin/env bash
# Column block qb_col_blk (config: blocks/col/col.env + icc2.cfg; flow/README.md).  On the build host:
#   qc18bacc/flow/blocks/col/run.sh pnr <tag>      pin DEF COL_PIN_DEF of the reference abstract COL_REFLEF
#                                                  (floorplan/abstract_pins.py), ICC2 (flow/icc2): libs init floorplan place cts route outputs in
#                                                  $B/icc2/col/<tag> (QC_PNR_FROM / QC_PNR_TO select a step range);
#                                                  every outputs netlist passes signoff/portcheck.py (also after eco),
#                                                  then fill (below)
#   qc18bacc/flow/blocks/col/run.sh fill <tag>     kit dummy metal fill (Calibre, fill_blk.sed) of the outputs GDS ->
#                                                  <run>/calibre/fill, then kit dummy OD / PO (odpo_blk.sed, R77) ->
#                                                  <run>/calibre/odpo; metal shapes as DEF FILLS (signoff/calibre/fill_def.py),
#                                                  fill-aware ICC2 extraction (flow/icc2/extract.tcl) -> out/<top>_<c>_pt.spef.gz
#                                                  for every sign-off corner c (R68; site.tcl corner table, env.sh qb_corners)
#   qc18bacc/flow/blocks/col/run.sh eco <tag>      one sign-off ECO round on the routed run: PrimeTime DMSA in every
#                                                  sign-off corner (signoff/pt/drv_eco.tcl: DRV, setup, hold) ->
#                                                  out/eco/pt_eco.tcl, applied by ICC2 (flow/icc2/eco.tcl: label route ->
#                                                  eco), outputs + fill of label eco; a later round starts from the label
#                                                  of out/ (out/label.txt: eco)
#   qc18bacc/flow/blocks/col/run.sh post <tag>     PrimeTime in every sign-off corner on the ICC2 netlist + SPEF (fails on a
#                                                  noise / min pulse width / min period violator, common/env.sh qb_pt), ETMs
#                                                  of every sign-off corner (R71; the chip top reads the same list; fails on
#                                                  MEXT-6 / MEXT-81 / MEXT-97 in an ETM log)
#   qc18bacc/flow/blocks/col/run.sh views <tag>    views for the chip top (blocks/top/run.sh views reads them): ICC2
#                                                  abstract LEF with ICC2's port antenna data + antenna / abutment / PG
#                                                  pin gates (flow/icc2/abstract.tcl,
#                                                  label QB_ICC2_LABEL [the label of out/, out/label.txt, as eco]) ->
#                                                  out/<top>.lef; ETM scan (etmcheck 3 ns: fails on an input pin
#                                                  without max_transition) of the post step's out/etm/<top>_<c>.lib
#   qc18bacc/flow/blocks/col/run.sh calibre <tag>  on the filled GDS of the fill step (metal: the one the SPEFs saw; + OD / PO): LVS source,
#                                                  Calibre LVS (lvs_case.sed), DRC (block deck drc_blk.sed), antenna
#                                                  -> <run>/calibre
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$here/col.env"
step=${1:?step}; tag=${2:?tag}; d=$B/icc2/col/$tag
export QB_SYN=$COL_SYN QB_PNR_PERIOD=$COL_PERIOD COL_TOP COL_PIN_DEF QB_ICC2_CFG=$here/icc2.cfg
echo "COL_STEP $step $tag $(date +%T)"
pt_env() {   # PrimeTime environment of the block sign-off script (signoff/pt/col_blk.tcl), run in the subshell of the caller
    qb_kit; set -a; . "$B/syn/$COL_SYN/run.env"; set +a
    export QC_SDC=$QBF/common/constraints.sdc QC_PT_HOOK= QC_PERIOD=$COL_PERIOD QC_PNR_OUT=$d QC_TOP=$COL_TOP
    cd "$d"
}
fill() {   # Calibre dummy metal + dummy OD / PO of out/<top>.gds; metal -> DEF FILLS -> fill-aware SPEFs (flow/icc2/extract.tcl), label of out/
    local o=$d/calibre C=$QBF/signoff/calibre w; mkdir -p "$o"
    QB55_FILL_SED="-f $C/fill_blk.sed" bash "$C/cal.sh" fill "$d/out/$COL_TOP.gds" "$COL_TOP" "$o/fill" > "$o/fill.log" 2>&1 \
        || { cat "$o/fill.log"; return 1; }
    grep -v '^CAL55_fill' "$o/fill.log"
    # dummy OD / PO (R77) on the metal-filled GDS, chip window = the DEF DIEAREA (signoff/calibre/odpo_blk.sed) -> odpo/<top>_fill.gds:
    # the GDS of Calibre LVS / DRC / antenna (calibre step).  FEOL dummies only: no effect on the metal SPEFs.
    # (DIEAREA as a rectangle or, as ICC2 writes it, a polygon: its bounding box)
    w=$(zcat "$d/out/$COL_TOP.def.gz" | awk '$1 == "UNITS" { u = $4 } $1 == "DIEAREA" { n = 0
        for (i = 2; i <= NF; i++) if ($i ~ /^-?[0-9.]+$/) v[n++] = $i / u
        x0 = x1 = v[0]; y0 = y1 = v[1]
        for (i = 2; i + 1 < n; i += 2) { x0 = v[i] < x0 ? v[i] : x0; x1 = v[i] > x1 ? v[i] : x1; y0 = v[i+1] < y0 ? v[i+1] : y0; y1 = v[i+1] > y1 ? v[i+1] : y1 }
        printf "%s %s %s %s", x0, y0, x1, y1; exit }')
    set -- $w; [ $# = 4 ] || { echo "COL_FAIL no DIEAREA in out/$COL_TOP.def.gz"; return 1; }
    printf 's#^VARIABLE xLB .*#VARIABLE xLB %s#\ns#^VARIABLE yLB .*#VARIABLE yLB %s#\ns#^VARIABLE xRT .*#VARIABLE xRT %s#\ns#^VARIABLE yRT .*#VARIABLE yRT %s#\n' "$@" > "$o/odpo_window.sed"
    QB77_ODPO_SED="-f $C/odpo_blk.sed -f $o/odpo_window.sed" bash "$C/cal.sh" odpo "$o/fill/${COL_TOP}_fill.gds" "$COL_TOP" "$o/odpo" > "$o/odpo.log" 2>&1 || { cat "$o/odpo.log"; return 1; }
    cat "$o/odpo.log"
    ( . "$C/kl.sh"; kl_run "$C/fill_def.py" -rd gds="$o/fill/DM.gds" -rd design="$COL_TOP" -rd out="$d/out/${COL_TOP}_fill.def" ) || return 1
    QB_ICC2_LABEL=$(cat "$d/out/label.txt") qb_icc2 "$d" extract || return 1
    grep '^extract' "$d/summary.txt" | tail -n 4
}
portcheck() {   # gate on the outputs netlist: port bits as the DC netlist, no port-to-port assign (signoff/portcheck.py)
    "$PY" -I "$QBF/signoff/portcheck.py" "$B/syn/$COL_SYN/$COL_TOP.v" "$d/out/$COL_TOP.v" "$COL_TOP"
}
case $step in
pnr) mkdir -p "$(dirname "$COL_PIN_DEF")"
     "$PY" -I "$QBF/floorplan/abstract_pins.py" "$COL_REFLEF" "$COL_PIN_DEF" || exit 1   # floorplan pin DEF (R72)
     on=0
     for s in libs init floorplan place cts route outputs; do
         [ "$s" = "${QC_PNR_FROM:-libs}" ] && on=1; [ $on = 1 ] || continue
         qb_icc2 "$d" $s "$([ $s = libs ] && echo icc2_lm_shell)" || exit 1
         [ $s = outputs ] && { portcheck && fill || exit 1; }
         [ "$s" = "${QC_PNR_TO:-outputs}" ] && break
     done
     cat "$d/summary.txt" | tail -40 ;;
eco) export QB_ECO_FROM=$(cat "$d/out/label.txt" 2>/dev/null || echo route)
     ( pt_env || exit 1
       QB_PT_SCRIPT=$QBF/signoff/pt/col_blk.tcl QB_ECO_CORNERS="$(qb_corners)" QB_ECO_NLIB=$d/$COL_TOP.nlib QB_ECO_BLOCK=$COL_TOP/$QB_ECO_FROM \
           qb_pt pt_eco.log pt_shell -multi_scenario -f "$QBF/signoff/pt/drv_eco.tcl" ) || exit 1
     rm -f "$d"/out/eco/work/.eco_ndm_*   # (the DMSA workers' NDM copies, ~0.42 GB each: disk, R71; their logs stay)
     cat "$d/out/eco/eco_summary.txt"
     qb_icc2 "$d" eco || exit 1
     QB_ICC2_LABEL=eco qb_icc2 "$d" outputs || exit 1
     portcheck && fill || exit 1
     grep '^eco' "$d/summary.txt" | tail -20 ;;
post) ( pt_env || exit 1
       r=0
       for c in $(qb_corners); do   # every corner is reported before a failure stops the step (R67)
           QC_CORNER=$c qb_pt "pt_blk_$c.log" pt_shell -f "$QBF/signoff/pt/col_blk.tcl" || r=1
           cat "pt_blk_$c.txt"
       done
       [ $r = 0 ] || exit 1
       for c in $(qb_corners); do
           QC_CORNER=$c qb_pt "etm_$c.log" pt_shell -f "$QBF/signoff/etm/etm.tcl" || r=1
           ! grep -m 3 'MEXT-6)\|MEXT-81\|MEXT-97' "etm_$c.log" || { echo "ETM $c: table limit / driving cell / feedthrough warnings"; r=1; }
           echo "ETM $c $(ls out/etm/ 2>/dev/null | grep -c '_lib.db$') dbs, $(grep -c 'RC-011' "etm_$c.log") RC-011 lines"
       done; exit $r ) || exit 1 ;;
views) QB_ICC2_LABEL=${QB_ICC2_LABEL:-$(cat "$d/out/label.txt" 2>/dev/null || echo route)} QB_PY=$PY qb_icc2 "$d" abstract || exit 1
     grep '^abstract' "$d/summary.txt" | tail -3
     for c in $(qb_corners); do "$PY" -I "$QBF/signoff/etm/etmcheck.py" "$d/out/etm/${COL_TOP}_$c.lib" 3.0 || exit 1; done ;;
fill) fill || exit 1 ;;
calibre) o=$d/calibre; C=$QBF/signoff/calibre; g=$o/odpo/${COL_TOP}_fill.gds
     [ "$g" -nt "$d/out/$COL_TOP.gds" ] || { echo "COL_FAIL $g missing or older than out/$COL_TOP.gds (run.sh fill)"; exit 1; }
     bash "$C/lvs_src.sh" "$d/out/${COL_TOP}_pg.v" "$o/col_src.spi" > "$o/src.log" 2>&1; r=$?; tail -3 "$o/src.log"; [ $r = 0 ] || exit 1
     r=0
     QB36_LVS_SED="-f $C/lvs_case.sed" bash "$C/cal.sh" lvs "$g" "$COL_TOP" "$o/col_src.spi" "$o/lvs" > "$o/lvs.log" 2>&1 || r=1
     QB36_DRC_SED="-f $C/drc_blk.sed" bash "$C/cal.sh" drc "$g" "$COL_TOP" "$o/drcb" > "$o/drcb.log" 2>&1 || r=1
     bash "$C/cal.sh" ant "$g" "$COL_TOP" "$o/ant" > "$o/ant.log" 2>&1 || r=1
     cat "$o/lvs.log" "$o/drcb.log" "$o/ant.log"; [ $r = 0 ] || exit 1 ;;
*) sed -n '2,/^set -u/{/^#/p}' "$0"; exit 1 ;;
esac
echo "COL_DONE $step $tag $(date +%T)"
