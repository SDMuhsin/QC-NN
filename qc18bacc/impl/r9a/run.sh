#!/usr/bin/env bash
# R9a (results/r9a.md): act-supply hard block qb_act2_blk (QB_ACT_S1M=1 + S2M + R8a act set) routed, DRC-clean, with
# LEF / ring LEF / ETMs, for the chip's west strip.  On tau from the repository root of the host-local tree; QC_BUILD
# default /tmp/$USER/qc18bacc/build:
#   qc18bacc/impl/r9a/run.sh syn            DC topographical 1.65 ns tt (topo.tcl: P&R DRV limits, final DRC fix, P&R die
#                                           context) + PT tt / ss -> syn/${QB_SYN:-r9a_act}
#   qc18bacc/impl/r9a/run.sh pins           column 0 act pin table $QC_BUILD/col_act_pins.txt (impl/r7c/col_pins.py)
#   qc18bacc/impl/r9a/run.sh pnr <tag>      full P&R (act.cfg) to detailed route; QB_W / QB_H die um (core = die - 10),
#                                           QB_DENS, QB_PNR_PERIOD (1.85), QB9_MAXTRAN / QB9_MAXFO (0.30 / 32),
#                                           QB_IO_LAT (0.55), QB_DR_ITER (30), QC_PNR_THREADS (7)
#   qc18bacc/impl/r9a/run.sh rt <src> <tag>  GRT (-allow_congestion) + DR from <src>/db/cts_rt.odb (route_rt.tcl)
#   qc18bacc/impl/r9a/run.sh post <tag>     def2spef ss / ff, PT sign-off tt / ss (impl/r7c/pt_blk.tcl, QB_PT_PERIOD 2.0),
#                                           DRC histogram
#   qc18bacc/impl/r9a/run.sh abs <tag>      abstract LEF (die SIZE), antenna check, act-pin abutment check vs column 0,
#                                           ring LEF, ETMs tt / ss / ff -> $QC_BUILD/r9a_blk/<tag>
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}
step=${1:?step}; tag=${2:-}
case $step in
syn) s=${QB_SYN:-r9a_act}
     QC_TOPO=1 QC_HOOK=$here/topo.tcl QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" \
       QB_FL=$here/qb_act2_blk.f "$root/qc18bacc/impl/run.sh" syn qb_act2_blk 1.65 $s &&
     QC_SDC=$root/qc18bacc/impl/constraints.sdc QC_PT_HOOK=$root/qc18bacc/impl/r8b/pt_s1.tcl QC_CLK=clk QC_CORES=8 \
       "$root/flow/tsmc65/sta/run_pt.sh" $s tt ss
     grep -c VIOLATED "$B/syn/$s/rpt/violators.rpt"; grep -A3 "Nets With Violations" "$B/syn/$s/rpt/qor.rpt"; echo R9A_SYN_DONE ;;
pins) python3 -I "$root/qc18bacc/impl/r7c/col_pins.py" "$B/r5b_blk/qb_col_blk_ring.lef" "$B/col_act_pins.txt" ;;
pnr) tag=${2:?tag}; DW=${QB9_DW:-780}; DH=${QB9_DH:-2420}
     QB_W=$(awk -v d=$DW 'BEGIN{print d-10}') QB_H=$(awk -v d=$DH 'BEGIN{print d-10}') QB7_YOFF=${QB7_YOFF:-$(awk -v d=$DH 'BEGIN{print 3110-d}')} \
     QB_SYN=${QB_SYN:-r9a_act} QB_IO_LAT=${QB_IO_LAT:-0.55} QC_PNR_THREADS=${QC_PNR_THREADS:-7} QB_DENS=${QB_DENS:-0.65} \
       QB7_MAXTRAN=${QB9_MAXTRAN:-0.30} QB7_MAXFO=${QB9_MAXFO:-32} QB7_DPL_ARGS=${QB9_DPL:-"-max_displacement {200 200}"} \
       QB_CFG=../r9a/act.cfg QB_PNR_PERIOD=${QB_PNR_PERIOD:-1.85} QB_RT_LOOPS=${QB_RT_LOOPS:-1} QB_DR_ITER=${QB_DR_ITER:-30} \
       /usr/bin/time -v -o "$B/pnr_$tag.time" "$root/qc18bacc/impl/pnr/run.sh" pnr "$tag" ;;
rt) src=${2:?src}; tag=${3:?tag}; d=$B/pnr/$tag    # route from <src>/db/cts_rt.odb (route_rt.tcl): QB9_GR_ITER, QB9_GR_ADJ, QB9_ANT, QB_DR_ITER
     rm -rf "$d"; mkdir -p "$d/db" "$d/rpt"; cp "$B/pnr/$src/config.tcl" "$B/pnr/$src/kit.env" "$B/pnr/$src/summary.txt" "$d/"
     cp -r "$B/pnr/$src/rc" "$d/"; cp "$B/pnr/$src/db/cts_rt.odb" "$B/pnr/$src/db/cts.sdc" "$d/db/"
     ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$d" && QC_FLOW=$FLOW QC_PNR_OUT=$d QB9_RUN=$d QC_PY=$TOOLS/env/bin/python3 QC_PNR_THREADS=${QC_PNR_THREADS:-16} \
       /usr/bin/time -v -o route.time "$TOOLS/env/bin/openroad" -no_init -no_splash -exit -log openroad.log "$here/route_rt.tcl" > openroad.out 2>&1 < /dev/null )
     echo "R9A_RT_DONE $tag rc $?" ;;
post) dir=$B/pnr/$tag
     QB_SPEF_CORNERS="${QB_SPEF_CORNERS:-tt ss ff}" "$root/qc18bacc/impl/pnr/run.sh" spef "$tag"
     ( . "$root/flow/tsmc65/common/tool.sh"; . "$dir/kit.env"; set -a; . "$(dirname "$NETLIST")/run.env"; set +a
       export QC_SDC=$root/qc18bacc/impl/constraints.sdc QC_PT_HOOK= QC_PERIOD=${QB_PT_PERIOD:-2.0}
       cd "$dir" || exit 1
       for c in ${QB_PT_CORNERS:-tt ss}; do
           QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c qc_tool "pt_blk_$c.log" pt_shell -f "$root/qc18bacc/impl/r7c/pt_blk.tcl"
           echo "PT_BLK $c errors $(grep -c '^Error' pt_blk_$c.log)"; cat "pt_blk_$c.txt"
       done )
     [ -f "$dir/rpt/drt.drc.rpt" ] && "$TOOLS/env/bin/python3" -I "$root/qc18bacc/impl/r5a/drc_hist.py" "$dir/rpt/drt.drc.rpt" > "$dir/drc_hist.txt"
     echo R9A_POST_DONE ;;
abs) dir=$B/pnr/$tag; o=$B/r9a_blk/$tag; mkdir -p "$o"
     ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$dir" && QC_FLOW=$FLOW QC_PNR_OUT=$dir QB9_ABS_OUT=$o QB7_COLPINS=${QB7_COLPINS:-$B/col_act_pins.txt} \
       QC_PY=$TOOLS/env/bin/python3 "$TOOLS/env/bin/openroad" -no_init -no_splash -exit -log abs.log "$here/abs.tcl" > abs.out 2>&1 < /dev/null )
     grep "QB9_" "$dir/abs.log"
     python3 -I "$here/lef_size.py" "$o/qb_act2_blk.lef" "$dir/abs.log" && ( cd "$o" && python3 -I "$root/qc18bacc/impl/r5b/lef_ring.py" qb_act2_blk.lef qb_act2_blk_ring.lef )
     ( . "$root/flow/tsmc65/common/tool.sh"; . "$dir/kit.env"; set -a; . "$(dirname "$NETLIST")/run.env"; set +a
       export QC_SDC=$root/qc18bacc/impl/constraints.sdc QC_PT_HOOK= QC_PERIOD=${QB_PT_PERIOD:-2.0}
       cd "$dir" || exit 1
       for c in tt ss ff; do
           QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c qc_tool "etm_$c.log" pt_shell -f "$root/qc18bacc/impl/r5a/etm.tcl"
       done   # serial: parallel extract_model runs share the temp file ./<top>_lib.lib in the run dir
       for c in tt ss ff; do echo "ETM $c errors $(grep -c '^Error' etm_$c.log)"; done )
     cp "$dir/out/qb_act2_blk.v" "$dir"/out/etm/qb_act2_blk_{tt,ss,ff}.lib "$dir"/out/etm/qb_act2_blk_{tt,ss,ff}_lib.db "$o/"
     ls -la "$o"; echo R9A_ABS_DONE ;;
*) sed -n '2,18p' "$0"; exit 1 ;;
esac
