#!/usr/bin/env bash
# South hub block qb_hub (config: blocks/hub/hub.env + hub.cfg; flow/README.md).  On the build host:
#   run.sh all <tag>       gate prod dio dr fin antd pt                                   (results/r34.md, r35.md)
#   run.sh gate <tag>      SDC + IO budget (sdc.py -> $QB9_W/cfg_<tag>/), init, floorplan (hub_mplace.py, hub_pins.py) + PDN,
#                          place (QC_PNR_TO place) -> db/place.odb; gate GRT of place.odb -> grt_pl/ (congestion report)
#   run.sh prod <tag>      ICG split / sizing, CTS .. IO latency L measured (cts/clk_lat.tcl) .. post-CTS DRV / setup / hold
#                          repair .. GRT + setup / hold / DRV repair at GRT parasitics + antenna repair -> db/grt.odb
#   run.sh dio <tag>       macro strap trim + macro-input buffers + diodes on db/grt.odb (route/hub_diodes.tcl)
#   run.sh dr <tag>        detailed route (route/dr.sh, 64 iterations, kit min-step / EOL rules, fillers after DR) + SPEF tt
#   run.sh fin <tag>       antenna check (route_dr) | abstract LEF + ring LEF ($B/r22_<tag>) | SPEF ss ff, PT + ETMs tt ss ff
#   run.sh antd <tag>      LEF-rule antenna check (signoff/antenna.tcl) of db/route_dr
#   run.sh pt <tag>        PT summary tt / ss (signoff/pt/hub_summary.tcl)
# Post-route steps (the R37 incremental ECO and R38 reroute steps of the r35_hubC -> r40_hub lineage were removed in R50;
# git history, results/r37.md, r38.md, r40.md):
#   run.sh copy <src> <tag>     copy of a run (run dir, cfg dir, kit.env fixed up) for a hold round
#   run.sh hold <tag> [margin 0.05]   setup pre-repair (repair/hub_setup_pre.tcl) + DRV / hold repair at tt + ss, full re-route
#                          (repair/hold_eco.sh; IO budget at the PT tt latency, per corner via repair/io_ref.tcl), env
#                          HUB_HOLD_DT (more dont_touch cells), QB37_RESIZE, HUB_HOLD_ANT (antenna repair after GRT with
#                          -ratio_margin <pct>; R40: 25; empty: none, R38)
#   run.sh drveco <tag>    PrimeTime DRV ECO ss + tt (signoff/pt/drv_eco.tcl) -> out/drv_eco_tt.tcl, applied by run.sh hold
#   run.sh signoff <tag>   SPEF tt, fin, LEF-rule antenna + PT tt / ss (signoff/pt/hub_signoff.tcl), antenna data in the
#                          LEF, ring LEF, ETM scan ($B/r22_<tag>); GDS (SRAM abstracts), LVS source, Calibre LVS (lvs_hub.sed +
#                          lvs_hubpg.sed) and antenna (drc_xsram.sed) -> $B/drc/<tag>
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$here/hub.env"
step=${1:?step}; tag=${2:?tag}; d=$B/pnr/$tag; W=$HUB_W
export QB_SYN=$HUB_SYN QB9_W=$W QC_PNR_THREADS=${QC_PNR_THREADS:-16}
export QC_SPEF_UNESC=1 QC_SPEF_ORFIX=1 QB15_GADJ_L=$HUB_GADJ_L
pnr() { QB_DPL_ARGS=$HUB_DPL_ARGS "$ROOT/flow/tsmc65/pnr/run_pnr.sh" "$here/hub.cfg" "$tag"; }
# PrimeTime of the run at one corner in its own work dir w_<PTW [log]>_<corner>: pt <corner> <script> <log> [VAR=value ...]
# (-> <run>/<log>_<corner>.log; extract_model writes ./<top>_lib.lib temporaries); status of common/env.sh qb_pt
pt() { local c=$1 s=$2 log=$3 w=${PTW:-$3}; shift 3
  ( . "$ROOT/flow/tsmc65/common/tool.sh"; . "$d/kit.env"; set -a; . "$B/syn/$QB_SYN/run.env"; set +a
    mkdir -p "$d/w_${w}_$c" "$d/rpt"; cd "$d/w_${w}_$c" || exit 1
    [ $# -gt 0 ] && export "$@"
    export QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c QB21_SDC=$W/cfg_$tag/qb_hub.sdc QB_PT_PERIOD=$HUB_PERIOD R31_PTHUB=$QBF/signoff/pt/hub.tcl
    qb_pt "$d/${log}_$c.log" pt_shell -f "$s" ) ; }
echo "HUB_STEP $step $tag $(date +%T)"
case $step in
all) for s in gate prod dio dr fin antd pt; do "$0" $s "$tag" || { echo "HUB_FAIL $s"; exit 1; }; done ;;
gate) qb_kit; mkdir -p "$W/cfg_$tag"
     ( "$PY" -I "$here/sdc.py" "$W/bnd_bits.txt" "$HUB_PERIOD" "$W/cfg_$tag/qb_hub.sdc" "$W/cfg_$tag/hub_io.tcl" || exit 1
       QC_PNR_TO=init pnr || exit 1
       ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$QBF/floorplan/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
       "$PY" -I "$QBF/floorplan/hub_mplace.py" "$d/macros.txt" "$d/mplace.tcl" "$HUB_SB" || exit 1
       x0=$(sed -n 's/^set ::QB9_X0 //p' "$d/mplace.tcl")
       "$PY" -I "$QBF/floorplan/hub_pins.py" "$W/bnd_bits.txt" "$HUB_COLLEF" "$x0" "$d/pins9_data.tcl" || exit 1
       QC_PNR_FROM=floorplan QC_PNR_TO=pdn pnr ) > "$B/pnr/${tag}_fp.out" 2>&1 || { echo HUB_FAIL fp; exit 1; }
     grep -h "MPLACE22\|MPLACE15 mid die\|MPLACE9 hub" "$B/pnr/${tag}_fp.out"
     QC_PNR_FROM=place QC_PNR_TO=place pnr > "$B/pnr/${tag}_place.out" 2>&1
     [ -s "$d/db/place.odb" ] || { echo HUB_FAIL place; exit 1; }
     echo HUB_PLACED $(date +%T)
     g=$d/grt_pl; mkdir -p "$g"
     ( cd "$d" && QC_PNR_OUT=$d /usr/bin/time -v -o "$g/grt.time" "$OR" -no_init -no_splash -exit -log "$g/grt.log" \
         "$QBF/route/hub_gate_grt.tcl" > "$g/grt.out" 2>&1 < /dev/null )
     grep -h "^R10B grt" "$g/grt.out"; grep -h "Elapsed\|Maximum res" "$g/grt.time" ;;
prod) QC_PNR_FROM=cts pnr
     [ -s "$d/db/grt.odb" ] || { echo HUB_FAIL grt; exit 1; } ;;
dio) "$QBF/common/or.sh" "$tag" "$QBF/route/hub_diodes.tcl" r29_dio.log; grep -h "R29_DIO" "$d/r29_dio.log"
     grep -q "R29_DIO done" "$d/r29_dio.log" || { echo HUB_DIO_FAILED; exit 1; } ;;
dr)  QB_DPL_ARGS=$HUB_DPL_ARGS QB8_DR_FILL=0 QB8_DR_THREADS=16 "$QBF/route/dr.sh" "$tag" ;;
fin) o=$B/r22_$tag; mkdir -p "$o"
     ( qb_kit; cd "$d" && QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit -log ant.log "$QBF/signoff/hub_check_ant.tcl" > ant.out 2>&1 < /dev/null
       grep -h "R21_ANT\|Found" "$d/ant.log" ) > "$d/ant_step.out" 2>&1 &
     ( ( qb_kit; cd "$d" && QC_PNR_OUT=$d QB21_ABS_OUT=$o "$OR" -no_init -no_splash -exit -log abs.log "$QBF/signoff/etm/hub_abs.tcl" > abs.out 2>&1 < /dev/null )
       grep "R21_ABS" "$d/abs.log"; "$PY" -I "$QBF/signoff/etm/lef_size.py" "$o/qb_hub.lef" "$d/abs.log"
       cp "$d/out/qb_hub.v" "$d"/out/etm/qb_hub_{tt,ss,ff}{.lib,_ref.txt,_lib.db} "$o/" 2>/dev/null; ls -la "$o"
       ( cd "$o" && "$PY" -I "$QBF/signoff/etm/lef_ring.py" qb_hub.lef qb_hub_ring.lef ) && echo HUB_RING_LEF ok ) > "$d/abs_step.out" 2>&1 &
     # SPEF ss / ff in parallel with PT + ETM tt (tt SPEF: dr step), then PT + ETM ss / ff (4 in parallel)
     ( for c in ss ff; do "$QBF/signoff/spef.sh" "$tag" $c > "$d/spef_$c.out" 2>&1 & done
       pt tt "$QBF/signoff/pt/hub.tcl" pt_hub QB21_ETM=0 & pt tt "$QBF/signoff/pt/hub.tcl" etm QB21_ETM=1 & qb_wait; r=$?
       for c in ss ff; do pt $c "$QBF/signoff/pt/hub.tcl" pt_hub QB21_ETM=0 & pt $c "$QBF/signoff/pt/hub.tcl" etm QB21_ETM=1 & done; qb_wait || r=1
       for c in tt ss ff; do cat "$d/pt_hub_$c.txt"; done; exit $r )
     r=$?; wait
     cp "$d"/out/etm/qb_hub_{tt,ss,ff}{.lib,_ref.txt,_lib.db} "$o/" 2>/dev/null; ls -la "$o"
     tail -n 3 "$d/ant_step.out" "$d/abs_step.out"; [ $r = 0 ] || { echo HUB_FAIL fin PT; exit 1; } ;;
antd) R29_DB=route_dr R29_TAG=dr "$QBF/common/or.sh" "$tag" "$QBF/signoff/antenna.tcl" r29_antd.log
     grep -hi "R29_ANTD\|found\|violat" "$d/r29_antd.log" | tail -4 ;;
pt)  for c in tt ss; do
       ( PTW=r31 pt $c "$QBF/signoff/pt/hub_summary.tcl" r31_pt31; r=$?; rm -rf "$d/w_r31_$c"
         grep -h "^R31PT\|^R31CLK\|^R31HOLD" "$d/r31_pt31_$c.log" | cut -c1-400
         echo "R31_PT $c PARA044 $(grep -c "PARA-044)" "$d/r31_pt31_$c.log")"; exit $r ) &
     done; qb_wait || exit 1 ;;
copy) src=${2:?src}; tag=${3:?tag}; d=$B/pnr/$tag; [ -e "$d" ] && { echo "HUB_FAIL $d exists"; exit 1; }
     cp -a "$B/pnr/$src" "$d"; mkdir -p "$W/cfg_$tag"
     for f in "$W/cfg_$src"/*; do sed "s#cfg_$src#cfg_$tag#g" "$f" > "$W/cfg_$tag/$(basename "$f")"; done
     sed -i "s#cfg_$src#cfg_$tag#g; s#/pnr/$src\b#/pnr/$tag#g" "$d/kit.env" ;;
hold) [ -e "$d/db/route_dr.odb" ] || touch "$d/db/route_dr.odb"     # hold_eco.tcl copies route_dr -> route_dr_prehold before its save
     export QB35_HDB=finish QB35_PER=$HUB_PERIOD QB35_HOLD_M=${3:-0.05} QB35_FILL_BEFORE=1 \
       QB37_FORCE_SAVE=1 QB35_THREADS=${QB35_THREADS:-14} QB35_IO_TCL=$QBF/repair/hub_io.tcl QB37_HUBIO=$W/cfg_$tag/hub_io.tcl \
       QB37_FR="actout 0.26" QB37_DONTTOUCH="u_top_U92356${HUB_HOLD_DT:+ $HUB_HOLD_DT}" \
       QB37_HPRE_TCL=$QBF/repair/hub_setup_pre.tcl QB37_SPCT=5 QB37_SM=0.0 \
       QB37_HPOST_TCL=${HUB_HOLD_ANT:+$QBF/repair/hub_hold_ant.tcl} QB38_ANT_MARGIN=${HUB_HOLD_ANT:-} \
       QB35_ECO_TCL=$([ -f "$d/out/drv_eco_tt.tcl" ] && echo "$d/out/drv_eco_tt.tcl")
     "$QBF/repair/hold_eco.sh" "$tag"
     rm -f "$d/db/route_dr_prehold.odb" ;;
drveco) for c in ss tt; do   # PrimeTime DRV ECO (signoff/pt/drv_eco.tcl): ss, then tt on top (out/drv_eco_tt.tcl = both)
       PTW=eco pt $c "$QBF/signoff/pt/drv_eco.tcl" drv_eco QB_PT_SCRIPT=$QBF/signoff/pt/hub.tcl \
         QB_PT_PRE_ECO=$([ $c = tt ] && echo "$d/out/drv_eco_ss.tcl") || exit 1
       grep "^drv\|QB_DRV_ECO" "$d/drv_eco_$c.log"
     done ;;
signoff) o=$B/r22_$tag; c=$B/drc/$tag; C=$QBF/signoff/calibre; mkdir -p "$c"
     "$QBF/signoff/spef.sh" "$tag" tt
     "$0" fin "$tag" > "$d/r38_fin.out" 2>&1; tail -4 "$d/r38_fin.out"
     R29_DB=finish R29_TAG=fin "$QBF/common/or.sh" "$tag" "$QBF/signoff/antenna.tcl" r29_antd.log &
     for k in tt ss; do
       ( PTW=r37 pt $k "$QBF/signoff/pt/hub_signoff.tcl" r37_pt; r=$?; rm -rf "$d/w_r37_$k"
         grep -h "^R37" "$d/r37_pt_$k.log"; cat "$d/pt_hub_$k.txt"; exit $r ) > "$d/r38_pt_$k.out" 2>&1 &
     done; qb_wait; ptr=$?
     grep -h "Found\|R29_ANTD" "$d/r29_antd.log" | tail -3; for k in tt ss; do grep "^R37\|PT_ERRORS\|violating\|slack_ns" "$d/r38_pt_$k.out" | cut -c1-200; done; [ $ptr = 0 ] || exit 1
     QB35_AOUT=$o/blkant.txt QB35_ADB=finish "$QBF/common/or.sh" "$tag" "$QBF/signoff/etm/blkant.tcl" r38_blkant.log
     LEF=$(. "$d/kit.env"; echo $LEF); "$PY" -I "$QBF/signoff/etm/blkant.py" "$LEF" "$o/blkant.txt" "$o/qb_hub.lef" "$o/qb_hub_ant.lef" | tail -3
     "$PY" -I "$QBF/signoff/etm/lef_ring.py" "$o/qb_hub_ant.lef" "$o/qb_hub_ant_ring.lef" | tail -2
     for k in tt ss ff; do "$PY" -I "$QBF/signoff/etm/etmcheck.py" "$o/qb_hub_$k.lib"; done
     # SRAM views for LVS / GDS (no layout / netlist in the kit, R38 F7): pin-only LVS stubs (lefstub.py) and LEF
     # abstract GDS cells with pin stack cuts (kl.sh kl_abs, lef2gds.py stack 1) of the run's macro LEFs -> $B/drc/<tag>/sram
     ML=$(cd "$d" && . ./kit.env && echo "$MACRO_LEFS"); S=$c/sram; mkdir -p "$S"; . "$C/kl.sh"
     "$PY" -I "$C/lefstub.py" "$S/sram_stub.spi" "$S/sram_stub.box" $ML && kl_abs "$tag" 1 "$S/sram_abs.gds" $ML > "$S/abs.log" 2>&1 \
       || { tail -3 "$S/abs.log"; echo "HUB_FAIL SRAM abstracts ($S)"; exit 1; }
     QB38_GDS_EXTRA=$S/sram_abs.gds bash "$C/gds.sh" "$tag" "$d/out/qb_hub.def" "$c/hub.gds" $ML > "$c/gds.log" 2>&1; r=$?; tail -2 "$c/gds.log"; [ $r = 0 ] || exit 1
     bash "$C/lvs_src.sh" "$d/out/qb_hub_pg.v" "$c/hub_src.spi" "$S/sram_stub.spi" > "$c/lvssrc.log" 2>&1; r=$?; tail -3 "$c/lvssrc.log"; [ $r = 0 ] || exit 1
     QB36_LVS_SED="-f $C/lvs_hub.sed -f $C/lvs_hubpg.sed" bash "$C/cal.sh" lvs "$c/hub.gds" qb_hub "$c/hub_src.spi" "$c/lvs" > "$c/lvs.log" 2>&1 &
     QB36_DRC_SED="-f $C/drc_xsram.sed" bash "$C/cal.sh" ant "$c/hub.gds" qb_hub "$c/ant" > "$c/ant.log" 2>&1 &
     qb_wait; r=$?; cat "$c/lvs.log" "$c/ant.log"; [ $r = 0 ] || exit 1 ;;
*) sed -n '2,28p' "$0"; exit 1 ;;
esac
echo "HUB_DONE $step $tag $(date +%T)"
