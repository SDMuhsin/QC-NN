#!/usr/bin/env bash
# R20 (results/r20.md): act block qb_act2_blk timing on top of impl/r19 (steps imported, not copied):
#   qc18bacc/impl/r20/run.sh cls <tag> [corners]  path-class breakdown (pt_cls.tcl) of $QC_BUILD/pnr/<tag> (needs out/*_<c>_pt.spef)
#   qc18bacc/impl/r20/run.sh syn                  impl/r13 syn recipe with QB_FL = r20/qb_act2_blk_chip_s1t.f, QC_HOOK = r20/topo.tcl
#                                                  (QB_SYN default r20_s1t)
#   qc18bacc/impl/r20/run.sh pnr <tag>            as impl/r19/run.sh pnr with QB_CFG = r20/act.cfg (band seed incl. S1T replicas)
#   qc18bacc/impl/r20/run.sh all <t>              chain <t>_p (pnr to CTS) -> <t>_s (post-CTS) -> <t>_c (route) -> post -> cls
#   qc18bacc/impl/r20/run.sh postcts | rt | post | abs ...  -> impl/r19/run.sh (-> impl/r16, impl/r9a)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
export QB_SYN=${QB_SYN:-r20_s1t}
step=${1:?step}
case $step in
cls) dir=$B/pnr/${2:?tag}
     ( . "$root/../flow/tsmc65/common/tool.sh"; . "$dir/kit.env"; set -a; . "$(dirname "$NETLIST")/run.env"; set +a
       export QC_SDC=$root/impl/constraints.sdc QC_PT_HOOK= QC_PERIOD=${QB_PT_PERIOD:-2.0} QB20_ROOT=$root
       cd "$dir" || exit 1
       for c in ${3:-tt}; do
           QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c qc_tool "r20_${QB20_PT:-cls}_$c.log" pt_shell -f "$here/pt_${QB20_PT:-cls}.tcl"
           echo "CLS $c errors $(grep -c "^Error" r20_${QB20_PT:-cls}_$c.log)"; cat "r20_${QB20_PT:-cls}_$c.txt" | head -40
       done ) ;;
syn) s=$QB_SYN    # as impl/r13/run.sh syn, with the R20 hook (topo.tcl) and file list
     QC_TOPO=1 QC_HOOK=$here/topo.tcl QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" \
       QB_FL=$here/qb_act2_blk_chip_s1t.f "$root/impl/run.sh" syn qb_act2_blk 1.65 $s &&
     QC_SDC=$root/impl/constraints.sdc QC_PT_HOOK=$root/impl/r8b/pt_s1.tcl QC_CLK=clk QC_CORES=8 \
       "$root/../flow/tsmc65/sta/run_pt.sh" $s tt ss
     grep "QB13_RPL\|QB20_RPL" "$B/syn/$s/dc.log"; grep -c VIOLATED "$B/syn/$s/rpt/violators.rpt"; grep -A3 "Nets With Violations" "$B/syn/$s/rpt/qor.rpt"
     echo R20_SYN_DONE ;;
pnr) tag=${2:?tag}; DW=${QB9_DW:-900}; DH=${QB9_DH:-1970}   # as impl/r19/run.sh pnr with QB_CFG = r20/act.cfg
     QB13_PINS=${QB13_PINS:-1} \
     QB_W=$((DW-10)) QB_H=$((DH-10)) QB7_YOFF=${QB7_YOFF:-$((3110-DH))} \
     QB_IO_LAT=${QB_IO_LAT:-0.55} QC_PNR_THREADS=${QC_PNR_THREADS:-16} QB_DENS=${QB_DENS:-0.55} \
       QB7_MAXTRAN=${QB9_MAXTRAN:-0.30} QB7_MAXFO=${QB9_MAXFO:-32} QB7_DPL_ARGS=${QB9_DPL:-"-max_displacement {200 200}"} \
       QB_CFG=../r20/act.cfg QB_PNR_PERIOD=${QB_PNR_PERIOD:-1.85} QB_RT_LOOPS=${QB_RT_LOOPS:-1} QB_DR_ITER=${QB_DR_ITER:-30} \
       /usr/bin/time -v -o "$B/pnr_$tag.time" "$root/impl/pnr/run.sh" pnr "$tag" ;;
all) t=${2:?tag}    # R20 production chain (PI target 2.30 ns): pnr to CTS -> post-CTS (R16 recipe) -> route (GRT adj 0.25,
     # antenna repair on, up to QB_DR_ITER 64) -> post (SPEF + PT tt / ss at QB_PT_PERIOD) -> cls (tt / ss).  P&R period
     # QB20_PNRP (2.20: ~4 % tool margin over the 2.30 sign-off period).
     # QB_IO_LAT 0.77 = the sign-off L of r19_mc (PT: mean of max launch / min capture latency 0.92 / 0.61); the R9a-R19
     # default 0.55 made the post-CTS hold repair see every ctl input -> ctx register path ~0.2 ns short (hold buffers on
     # the tgo -> is_v trunk, 0.39 ns of the r19_mc cin2reg path).  QB20_FROM=postcts: start at the post-CTS step.
     pp=${QB20_PNRP:-2.20}; export QB_IO_LAT=${QB_IO_LAT:-0.77}
     [ "${QB20_FROM:-pnr}" = pnr ] && { QC_PNR_TO=cts QB_PNR_PERIOD=$pp "$here/run.sh" pnr ${t}_p || exit 1; }
     QB_PNR_PERIOD_RT=$pp QB16_PEN=${QB16_PEN:-0.01} QB16_OVF=${QB16_OVF:-0.05} QB16_S1INF=${QB16_S1INF:-1} "$here/run.sh" postcts ${t}_p ${t}_s || exit 1
     QB9_GR_ADJ=${QB9_GR_ADJ:-0.25} QB9_GR_ITER=${QB9_GR_ITER:-10} QB9_ANT=${QB9_ANT:-1} QB_DR_ITER=${QB_DR_ITER:-64} \
       QC_PNR_THREADS=${QC_PNR_THREADS:-14} "$here/run.sh" rt ${t}_s ${t}_c
     QB_PT_PERIOD=${QB_PT_PERIOD:-2.30} "$here/run.sh" post ${t}_c
     QB_PT_PERIOD=${QB_PT_PERIOD:-2.30} "$here/run.sh" cls ${t}_c "tt ss"
     echo R20_ALL_DONE $t ;;
*)   exec "$here/../r19/run.sh" "$@" ;;
esac
