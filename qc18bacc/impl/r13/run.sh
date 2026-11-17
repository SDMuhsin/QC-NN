#!/usr/bin/env bash
# R13 (results/r13.md): qb_act2_blk with QB_ACT_RPL, on top of impl/r9a/run.sh (all steps imported, not copied):
#   qc18bacc/impl/r13/run.sh syn              QB_FL = r13/qb_act2_blk.f, QC_HOOK = r13/topo.tcl (no register merging of
#                                             the replicas), QB_SYN default r13_act
#                                             QB13_FL=qb_act2_blk_chip.f: chip-cone wrapper (QB13_BLK_CHIP), e.g. QB_SYN=r13_actc
#   qc18bacc/impl/r13/run.sh pnr <tag>        as impl/r9a/run.sh pnr with QB_CFG = r13/act.cfg (S1 padding QB13_PAD, default 1
#                                             site) and QB_DENS default 0.55; die QB9_DW x QB9_DH default 900 x 1970
#   qc18bacc/impl/r13/run.sh <step> ...       pins | rt | post | abs -> impl/r9a/run.sh with QB_SYN=r13_act
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
export QB_SYN=${QB_SYN:-r13_act}
step=${1:?step}
case $step in
syn) export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD; s=$QB_SYN
     QC_TOPO=1 QC_HOOK=$here/topo.tcl QC_COMPILE="compile_ultra -no_autoungroup -gate_clock -spg" \
       QB_FL=$here/${QB13_FL:-qb_act2_blk.f} "$root/impl/run.sh" syn qb_act2_blk 1.65 $s &&
     QC_SDC=$root/impl/constraints.sdc QC_PT_HOOK=$root/impl/r8b/pt_s1.tcl QC_CLK=clk QC_CORES=8 \
       "$root/../flow/tsmc65/sta/run_pt.sh" $s tt ss
     grep "QB13_RPL" "$B/syn/$s/dc.log"; grep -c VIOLATED "$B/syn/$s/rpt/violators.rpt"; grep -A3 "Nets With Violations" "$B/syn/$s/rpt/qor.rpt"
     echo R13_SYN_DONE ;;
pnr) tag=${2:?tag}; export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; DW=${QB9_DW:-900}; DH=${QB9_DH:-1970}
     QB_W=$(awk -v d=$DW 'BEGIN{print d-10}') QB_H=$(awk -v d=$DH 'BEGIN{print d-10}') QB7_YOFF=${QB7_YOFF:-$(awk -v d=$DH 'BEGIN{print 3110-d}')} \
     QB_IO_LAT=${QB_IO_LAT:-0.55} QC_PNR_THREADS=${QC_PNR_THREADS:-16} QB_DENS=${QB_DENS:-0.55} \
       QB7_MAXTRAN=${QB9_MAXTRAN:-0.30} QB7_MAXFO=${QB9_MAXFO:-32} QB7_DPL_ARGS=${QB9_DPL:-"-max_displacement {200 200}"} \
       QB_CFG=../r13/act.cfg QB_PNR_PERIOD=${QB_PNR_PERIOD:-1.85} QB_RT_LOOPS=${QB_RT_LOOPS:-1} QB_DR_ITER=${QB_DR_ITER:-30} \
       /usr/bin/time -v -o "$QC_BUILD/pnr_$tag.time" "$root/impl/pnr/run.sh" pnr "$tag" ;;
*)   exec "$root/impl/r9a/run.sh" "$@" ;;
esac
