#!/bin/bash
# R15 detailed route of a GRT-only result (on tau): drrun.sh <tag> <gtag> [env ...]
# links db/grt.odb -> db/grt_<gtag>.odb, db/grt.sdc -> db/place.sdc, route.guide -> grt_<gtag>/route.guide (the run has no
# CTS: QB_POSTCTS 0 / place.odb, as R12), then impl/r10b/run.sh dr (= impl/r8 dr.tcl, RSS log rpt/dr_rss.txt);
# defaults QB8_DR_FILL 0 (fillers after DR), QB8_DR_THREADS 12, QB_DR_ITER from hub.cfg (20) unless given.
t=$1; g=$2; shift 2
cd ${QB12_SNAP:-/tmp/ckp908/qc18bacc/r10b_snap}
B=/tmp/ckp908/qc18bacc/build; d=$B/pnr/$t
export QC_BUILD=$B QB_SYN=r10_rpw QB9_W=$B/r10b_ww QB10_SRD=0
[ -s $d/db/grt_$g.odb ] || { echo "no $d/db/grt_$g.odb"; exit 1; }
ln -sfn grt_$g.odb $d/db/grt.odb; ln -sfn place.sdc $d/db/grt.sdc; ln -sfn grt_$g/route.guide $d/route.guide
env QB8_DR_FILL=0 QB8_DR_THREADS=${THR:-12} "$@" qc18bacc/impl/r10b/run.sh dr $t > $B/${t}_dr.out 2>&1 < /dev/null
