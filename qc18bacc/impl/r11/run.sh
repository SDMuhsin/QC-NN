#!/usr/bin/env bash
# R11 hierarchical top-level assembly (results/r11.md), on tau from the snapshot root, QC_BUILD as R8:
#   qc18bacc/impl/r11/run.sh nl              top netlist (top_nl.py) from the R10b hub partition of r10_rpw
#                                            ($QB11_PART [$B/r10b_ww]/qb_chip_r9b_c.v) -> $B/r11/top_r11.v (+ equiv / act map)
#   qc18bacc/impl/r11/run.sh hubfp <tag>     hub floorplan (R10b recipe: mplace10.py, pins9.py, pins10.tcl, impl/r10b/hub.cfg)
#                                            in an own work dir $B/r11/hubw (links to the R10b partition), to the
#                                            floorplan step, then the hub abstract LEF (abs.tcl) -> $B/r11/abs/qb_hub.lef
#   qc18bacc/impl/r11/run.sh abs             act proxy LEF (act_lef.py), hub / act proxy liberty (blk_lib.py, sdc.py budgets)
#   qc18bacc/impl/r11/run.sh fp <tag>        top init, macro dump, fp11.py floorplan + interface table (iface.txt), floorplan + pdn
#   qc18bacc/impl/r11/run.sh pnr <tag>       place .. GRT (QB_GRT_STOP 1) with impl/r11/top.cfg
#   qc18bacc/impl/r11/run.sh sta <tag>       timing probe (sta_rt.tcl: DRV repair unlegalised + classes.tcl), nothing saved
#   qc18bacc/impl/r11/run.sh dr <tag>        detailed route in a fresh process (impl/r8/run.sh dr: RSS log, SPEF)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad; PY=$TOOLS/env/bin/python3
R=$B/r11; mkdir -p "$R/abs"
PART=${QB11_PART:-$B/r10b_ww}
kit() { . "$root/flow/tsmc65/common/tool.sh"
        QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY; }
step=${1:?step}
case $step in
nl)  cd "$R" && python3 -I "$here/top_nl.py" "$PART/qb_chip_r9b_c.v" top_r11 ;;
hubfp) tag=${2:?tag}; d=$B/pnr/$tag; kit; W=$R/hubw; mkdir -p "$W/cfg_$tag"
     for f in qb_hub_c.v bnd_bits.txt; do ln -sf "$PART/$f" "$W/$f"; done
     "$PY" -I "$root/qc18bacc/impl/r9b/sdc.py" "$W/bnd_bits.txt" "${QB9_PER:-1.85}" "$W/cfg_$tag/qb_hub.sdc" "$W/cfg_$tag/hub_io.tcl" || exit 1
     export QB9_W=$W
     QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$root/qc18bacc/impl/r10b/hub.cfg" "$tag" || exit 1
     ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
     "$PY" -I "$root/qc18bacc/impl/r10b/mplace10.py" "$d/macros.txt" "$d/mplace.tcl" || exit 1
     x0=$(sed -n 's/^set ::QB9_X0 //p' "$d/mplace.tcl")
     "$PY" -I "$root/qc18bacc/impl/r9b/pins9.py" "$W/bnd_bits.txt" "$B/r5b_blk/qb_col_blk.lef" "$x0" "$d/pins9_data.tcl" || exit 1
     QC_PNR_FROM=floorplan QC_PNR_TO=floorplan "$root/flow/tsmc65/pnr/run_pnr.sh" "$root/qc18bacc/impl/r10b/hub.cfg" "$tag" || exit 1
     ( cd "$d" && QB_DB=$d/db/floorplan.odb QB_LEF=$R/abs/qb_hub_abs.lef "$OR" -no_init -no_splash -exit -log abs.log "$here/abs.tcl" > abs.out 2>&1 < /dev/null )
     tail -3 "$d/abs.out"; ls -la "$R/abs" ;;
abs) cd "$R/abs" || exit 1; yh=$(sed -n 's/^set ::QB9_H //p' "$B/pnr/${QB11_HUB:-r11_hub}/mplace.tcl")
     "$PY" -I "$here/act_lef.py" "$B/col_act_pins.txt" qb_hub_abs.lef "$R/top_r11_bpins.txt" "${QB11_ACT_W:-780}" "${QB11_ACT_H:-2420}" 860 "$yh" . || exit 1
     "$PY" -I "$here/blk_lib.py" "${QB11_PER:-1.85}" qb_hub.lef "$PART/bnd_bits.txt" hub qb_hub || exit 1
     "$PY" -I "$here/blk_lib.py" "${QB11_PER:-1.85}" qb_act2_blk.lef - act qb_act2_blk || exit 1
     for c in tt ss ff; do "$PY" -I "$root/qc18bacc/impl/r7b/etm_fix.py" "$B/r5b_blk/qb_col_blk_${c}_ins.lib" "qb_col_blk_${c}_insfix.lib" | grep -c ETM_FIX; done
     ls -la ;;
fp)  tag=${2:?tag}; d=$B/pnr/$tag; kit
     QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/top.cfg" "$tag" || exit 1
     ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
     "$PY" -I "$here/fp11.py" "$d/macros.txt" "$R/abs" "$d/mplace.tcl" "$B/r5b_blk/qb_col_blk.lef" "$R/top_r11_bpins.txt" || exit 1
     QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/top.cfg" "$tag" ;;
pnr) tag=${2:?tag}; kit
     QB_GRT_STOP=${QB_GRT_STOP:-1} QC_PNR_FROM=${QC_PNR_FROM:-place} "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/top.cfg" "$tag" ;;
sta) tag=${2:?tag}; d=$B/pnr/$tag; kit; cd "$d" || exit 1      # timing probe sta_rt.tcl (QB_DB, QB11_RD, QB11_CORNER)
     QB11_DIR=$here QC_PNR_OUT=$d /usr/bin/time -v -o sta_rt.time "$OR" -no_init -no_splash -exit -log sta_rt.log "$here/${QB11_STA_TCL:-sta_rt.tcl}" > sta_rt.out 2>&1 < /dev/null
     grep -h "r11 class\|Error\|ERROR" sta_rt.log | tail -30; grep -h "Elapsed\|Maximum res" sta_rt.time ;;
dr)  tag=${2:?tag}; QB8_DR_THREADS=${QB8_DR_THREADS:-6} "$root/qc18bacc/impl/r8/run.sh" dr "$tag" ;;
*) sed -n '2,14p' "$0"; exit 1 ;;
esac
echo "R11_DONE $step"
