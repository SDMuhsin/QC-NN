#!/usr/bin/env bash
# R7c (results/r7c.md): act supply qb_act2_blk (qb_act2 + act distribution, qb_act2_blk.sv) as a routed hard block for
# the west strip, on tau from the repository root of the host-local tree, QC_BUILD default /tmp/$USER/qc18bacc/build:
#   qc18bacc/impl/r7c/run.sh syn            DC topographical 1.65 ns tt (impl/run.sh all: + pre-route PT tt / ss),
#                                           tag r7c_act_tt_p1.65_topo; QB_UTIL_T / QB_ASPECT: topo context
#   qc18bacc/impl/r7c/run.sh pins           column 0 act pin table $QC_BUILD/col_act_pins.txt (col_pins.py of
#                                           $QC_BUILD/r5b_blk/qb_col_blk_ring.lef)
#   qc18bacc/impl/r7c/run.sh pnr  <tag>     P&R act.cfg; QB_W / QB_H core um (die + 10), QB_DENS, QB_RD, QB_PNR_PERIOD
#                                           (default 2.0), QB_DR_ITER (default 20), QB_IO_LAT, QC_PNR_THREADS
#   qc18bacc/impl/r7c/run.sh post <tag>     SPEF ss / ff, PT sign-off tt / ss (pt_blk.tcl, QB_PT_PERIOD default 2.0),
#                                           DR marker histogram
#   qc18bacc/impl/r7c/run.sh abs  <tag>     abstract LEF + ETMs tt / ss / ff (impl/r5a/post.sh abs etm), ring LEF
#                                           (impl/r5b/lef_ring.py) -> $QC_BUILD/r7c_blk
#   qc18bacc/impl/r7c/run.sh abs0 <tag> [db] pre-route stand-ins -> $QC_BUILD/r7c_blk: abstract LEF of checkpoint <db>
#                                           (default pdn: die, exact pins, PG straps) + ring LEF, ETMs tt / ss / ff of the
#                                           DC netlist with DC topographical parasitics (etm_dc.tcl)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}
step=${1:?step}; tag=${2:-}
case $step in
syn) QC_TOPO=1 QC_HOOK=$here/topo_act.tcl QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" QB_FL=$here/qb_act2_blk.f \
       "$root/qc18bacc/impl/run.sh" all qb_act2_blk 1.65 ${QB_SYN_TAG:-r7c_act_tt_p1.65_topo} ;;
pins) python3 -I "$here/col_pins.py" "$B/r5b_blk/qb_col_blk_ring.lef" "$B/col_act_pins.txt" ;;
pnr) QB_CFG=../r7c/act.cfg QB_PNR_PERIOD=${QB_PNR_PERIOD:-2.0} QB_RT_LOOPS=${QB_RT_LOOPS:-0} QB_DR_ITER=${QB_DR_ITER:-20} \
       "$root/qc18bacc/impl/pnr/run.sh" pnr "$tag" ;;
post) dir=$B/pnr/$tag
     QB_SPEF_CORNERS="ss ff" "$root/qc18bacc/impl/pnr/run.sh" spef "$tag"
     ( . "$root/flow/tsmc65/common/tool.sh"; . "$dir/kit.env"; set -a; . "$(dirname "$NETLIST")/run.env"; set +a
       export QC_SDC=$root/qc18bacc/impl/constraints.sdc QC_PT_HOOK= QC_PERIOD=${QB_PT_PERIOD:-2.0}
       cd "$dir" || exit 1
       for c in ${QB_PT_CORNERS:-tt ss}; do
           QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c qc_tool "pt_blk_$c.log" pt_shell -f "$here/pt_blk.tcl"
           echo "PT_BLK $c errors $(grep -c '^Error' pt_blk_$c.log)"; cat "pt_blk_$c.txt"
       done )
     [ -f "$dir/rpt/drt.drc.rpt" ] && "$TOOLS/env/bin/python3" -I "$root/qc18bacc/impl/r5a/drc_hist.py" "$dir/rpt/drt.drc.rpt" > "$dir/drc_hist.txt"
     echo R7C_POST_DONE ;;
abs) "$root/qc18bacc/impl/r5a/post.sh" "$tag" "abs etm"
     d=$B/pnr/$tag/out; mkdir -p "$B/r7c_blk"
     cp "$d/qb_act2_blk.lef" "$d"/etm/qb_act2_blk_{tt,ss,ff}{.lib,_lib.db} "$B/r7c_blk/"
     cd "$B/r7c_blk" && python3 -I "$root/qc18bacc/impl/r5b/lef_ring.py" qb_act2_blk.lef qb_act2_blk_ring.lef
     echo R7C_ABS_DONE ;;
abs0) dir=$B/pnr/$tag; db=${3:-pdn}; mkdir -p "$B/r7c_blk"
     printf 'source $::env(QC_FLOW)/pnr/or/lib.tcl\nset ::OUT %s\nsource $::OUT/config.tcl\nqc_config\nqc_read_liberty\nread_db %s/db/%s.odb\nwrite_abstract_lef -bloat_factor 0 %s/qb_act2_blk.lef\nexit\n' \
         "$dir" "$dir" "$db" "$B/r7c_blk" > "$B/r7c_blk/abs0.tcl"
     ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$dir" && QC_FLOW=$FLOW QC_PNR_OUT=$dir QC_PY=$TOOLS/env/bin/python3 \
       "$TOOLS/env/bin/openroad" -no_init -no_splash -exit -log "$B/r7c_blk/abs0.log" "$B/r7c_blk/abs0.tcl" > /dev/null 2>&1 < /dev/null )
     ( cd "$B/r7c_blk" && python3 -I "$root/qc18bacc/impl/r5b/lef_ring.py" qb_act2_blk.lef qb_act2_blk_ring.lef )
     echo "ABS0 LEF pins $(grep -c '^  PIN' $B/r7c_blk/qb_act2_blk.lef) $(grep -m1 SIZE $B/r7c_blk/qb_act2_blk.lef)"
     ( . "$root/flow/tsmc65/common/tool.sh"; s=$B/syn/${QB_SYN:-r7c_act_tt_p1.65_topo}; set -a; . "$s/run.env"; set +a
       export QC_SDC=$root/qc18bacc/impl/constraints.sdc QC_PT_HOOK= QC_PERIOD=${QB_PT_PERIOD:-2.0} QB7_SYN_DIR=$s QB7_OUT=$B/r7c_blk
       cd "$B/r7c_blk" && for c in tt ss ff; do QC_CORNER=$c qc_tool "etm_pre_$c.log" pt_shell -f "$here/etm_dc.tcl"
         echo "ETM_PRE $c errors $(grep -c '^Error' etm_pre_$c.log)"; done )
     ls "$B/r7c_blk" ;;
*) sed -n '2,18p' "$0"; exit 1 ;;
esac
