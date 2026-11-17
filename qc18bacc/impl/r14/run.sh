#!/usr/bin/env bash
# R14 hierarchical top, second iteration (results/r14.md), on tau from the snapshot root, QC_BUILD as R8 / R11:
#   qc18bacc/impl/r14/run.sh abs           hub / act proxies + liberty (abs14.py) -> $B/r14/abs (+ column insfix libs of R11)
#   qc18bacc/impl/r14/run.sh fp <tag>      top init, macro dump, fp14.py floorplan, floorplan + pdn (impl/r14/top14.cfg)
#   qc18bacc/impl/r14/run.sh pnr <tag>     place .. GRT (QB_GRT_STOP 1)
#   qc18bacc/impl/r14/run.sh ovf <tag>     GRT overflow by region (ovf14.py)
#   qc18bacc/impl/r14/run.sh sta <tag>     timing probe on db QB_DB (impl/r11/sta_rt.tcl with QB11_RD 0)
#   qc18bacc/impl/r14/run.sh dr <tag>      detailed route in a fresh process (impl/r8/run.sh dr: RSS log, SPEF)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad; PY=$TOOLS/env/bin/python3
R=$B/r14; mkdir -p "$R/abs"
export QB11_ABS=${QB11_ABS:-$R/abs}
kit() { . "$root/flow/tsmc65/common/tool.sh"
        QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY; }
step=${1:?step}
case $step in
abs) cd "$QB11_ABS" || exit 1; yh=$(sed -n 's/^set ::QB9_H //p' "$B/pnr/${QB11_HUB:-r11_hub}/mplace.tcl")
     QB14_TOPV=${QB14_TOPV:-$B/r11/top_r11.v} "$PY" -I "$here/abs14.py" "$B/r11/abs/qb_hub_abs.lef" "$B/r5b_blk/qb_col_blk.lef" "$B/col_act_pins.txt" "$B/r11/top_r11_bpins.txt" \
         "$yh" . "${QB11_PER:-1.85}" "${QB11_PART:-$B/r10b_ww}/bnd_bits.txt" || exit 1
     for c in tt ss ff; do ln -sf "$B/r11/abs/qb_col_blk_${c}_insfix.lib" .; done; ls -la ;;
fp)  tag=${2:?tag}; d=$B/pnr/$tag; kit
     QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/top14.cfg" "$tag" || exit 1
     ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
     "$PY" -I "$here/fp14.py" "$d/macros.txt" "$QB11_ABS" "$d/mplace.tcl" || exit 1
     QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/top14.cfg" "$tag" ;;
pnr) tag=${2:?tag}; kit
     QB_GRT_STOP=${QB_GRT_STOP:-1} QC_PNR_FROM=${QC_PNR_FROM:-place} "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/top14.cfg" "$tag" ;;
ovf) tag=${2:?tag}; d=$B/pnr/$tag; "$PY" -I "$here/ovf14.py" "$d/rpt/gr_congestion.rpt" "$d/mplace.tcl" | tee "$d/rpt/ovf14.txt" ;;
sta) tag=${2:?tag}; d=$B/pnr/$tag; kit; cd "$d" || exit 1
     QB11_RD=${QB11_RD:-0} QB11_DIR=$root/qc18bacc/impl/r11 QC_PNR_OUT=$d /usr/bin/time -v -o sta_rt.time "$OR" -no_init -no_splash -exit -log sta_rt.log "$root/qc18bacc/impl/r11/sta_rt.tcl" > sta_rt.out 2>&1 < /dev/null
     grep -h "r11 class\|Error\|ERROR" sta_rt.log | tail -30 ;;
dr)  tag=${2:?tag}; QB8_DR_THREADS=${QB8_DR_THREADS:-8} "$root/qc18bacc/impl/r8/run.sh" dr "$tag" ;;
*) sed -n '2,9p' "$0"; exit 1 ;;
esac
echo "R14_DONE $step"
