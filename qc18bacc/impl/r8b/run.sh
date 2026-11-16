#!/usr/bin/env bash
# R8b (results/r8b.md): act-supply hard block qb_act2_blk with the S1 restructuring QB_ACT_S1M, R7c flow (impl/r7c),
# on tau from the repository root of a host-local tree; QC_BUILD default /tmp/$USER/qc18bacc/build:
#   qc18bacc/impl/r8b/run.sh syn <v>       DC topographical 1.65 ns tt + PT tt / ss of qb_act2_blk_s1m<v>.f -> syn/r8b_s1m<v>
#   qc18bacc/impl/r8b/run.sh pnr <v> <tag> R7c B4 P&R recipe (820 x 2420, dens 0.80, max_tran 0.40, max_fo 64, DPL window
#                                          500 um) with QB_IO_LAT 0.55 (R7c's 0.85 was the column value), up to CTS
#                                          (v = base: R7c's DC netlist r7c_act_tt_p1.65_topo)
#   qc18bacc/impl/r8b/run.sh rt <v> <tag>  the route step's PRE_ROUTE_TCL only (post-CTS setup / hold repair ->
#                                          db/cts_rt.odb): flow from route, stopped when cts_rt.odb is written
#   qc18bacc/impl/r8b/run.sh grt <tag>     impl/r7c/grt_probe.tcl on db/cts_rt.odb (QB7_DB) + congestion classes
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}
step=${1:?step}
case $step in
syn) v=${2:?v}
     QC_TOPO=1 QC_HOOK=$root/qc18bacc/impl/r7c/topo_act.tcl QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" \
       QB_FL=$here/qb_act2_blk_s1m$v.f "$root/qc18bacc/impl/run.sh" all qb_act2_blk 1.65 r8b_s1m$v ;;
pnr) v=${2:?v}; tag=${3:?tag}
     syn=r8b_s1m$v; [ "$v" = base ] && syn=r7c_act_tt_p1.65_topo
     QB_SYN=$syn QB_IO_LAT=${QB_IO_LAT:-0.55} QC_PNR_THREADS=${QC_PNR_THREADS:-5} QB_W=810 QB_H=2410 QB_DENS=0.80 \
       QB7_MAXTRAN=0.40 QB7_MAXFO=64 QB7_DPL_ARGS="-max_displacement {500 500}" QC_PNR_TO=${QC_PNR_TO:-cts} \
       QB_CFG=../r7c/act.cfg QB_PNR_PERIOD=${QB_PNR_PERIOD:-2.0} QB_RT_LOOPS=${QB_RT_LOOPS:-0} QB_DR_ITER=${QB_DR_ITER:-20} \
       "$root/qc18bacc/impl/pnr/run.sh" pnr "$tag" ;;
rt) v=${2:?v}; tag=${3:?tag}; dir=$B/pnr/$tag
     QC_PNR_FROM=route QC_PNR_TO=route "$0" pnr "$v" "$tag" > "$dir/rt.out" 2>&1 &
     until [ -f "$dir/db/cts_rt.odb" ] && [ "$(stat -c %s "$dir/db/cts_rt.odb")" = "$(sleep 30; stat -c %s "$dir/db/cts_rt.odb")" ]
     do sleep 20; done
     for p in $(pgrep -u "$USER" openroad); do [ "$(readlink /proc/$p/cwd)" = "$dir" ] && kill "$p"; done; sleep 2
     grep "^postcts" "$dir/summary.txt"; echo "R8B_RT_DONE $tag" ;;
grt) tag=${2:?tag}; dir=$B/pnr/$tag
     ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$dir" && QC_FLOW=$FLOW QC_PNR_OUT=$dir QB7_RUN=$dir QC_PY=$TOOLS/env/bin/python3 /usr/bin/time -v -o grt_probe.time \
       "$TOOLS/env/bin/openroad" -no_init -no_splash -exit -log grt_probe.log "$root/qc18bacc/impl/r7c/grt_probe.tcl" > grt_probe.out 2>&1 < /dev/null )
     grep -A12 "Final congestion report\|Layer  *Resource" "$dir/grt_probe.log" | head -30
     python3 -I "$here/cong_cls.py" "$dir/rpt/grt_probe_congestion.rpt" ;;
*) sed -n '2,10p' "$0"; exit 1 ;;
esac
