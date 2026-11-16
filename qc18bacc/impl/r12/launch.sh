#!/bin/bash
# R12 (results/r12.md): area-for-routability runs of the R10b wA4 hub (netlist r10_rpw, gpl, no srd) at another band
# height, same flow as wA4: impl/r10b/run.sh fp + pnr up to place, then GRT from place.odb with 3 congestion iterations
# (grt_pl3) and the R10b overflow analysis.  usage (on tau, from the snapshot root): launch.sh <tag> [env ...]
# e.g. launch.sh r12_b650 QB_SB=650 ;  wA4 = QB_SB=450.  Extra env (e.g. QB9_MAXTRAN / QB9_MAXFO) passes through.
t=$1; shift
cd ${QB12_SNAP:-/tmp/ckp908/qc18bacc/r10b_snap}
B=/tmp/ckp908/qc18bacc/build
export QC_BUILD=$B QB_SYN=r10_rpw QB9_W=$B/r10b_ww QB10_SRD=0
env QB_SB=450 QB_TD=0 QB_RD=0 QB_DPL_ARGS="-max_displacement 500" QB9_CHBLK=40 QB9_GPL2=1 QB_POSTCTS=0 QB9_GR_ITER=3 \
    QC_PNR_SET="QB_GPL_INCR_DENS 0.86" QC_PNR_THREADS=${THR:-8} "$@" bash -c "
  echo R12_START \$(date +%T)
  qc18bacc/impl/r10b/run.sh fp $t || exit 1
  QC_PNR_TO=place qc18bacc/impl/r10b/run.sh pnr $t || exit 1
  echo R12_PLACED \$(date +%T)
  QB_GI=3 QB_GTAG=pl3 QB_DB=place qc18bacc/impl/r10b/run.sh grt $t place || exit 1
  qc18bacc/impl/r10b/run.sh ana $t pl3 > /dev/null
  echo R12_DONE \$(date +%T)" > $B/$t.out 2>&1 < /dev/null
