#!/bin/bash
# usage: r10b_pnr.sh <tag> [env assignments...]   pnr only (place .. GRT) of an R10b hub run whose fp is done
t=$1; shift
cd /tmp/ckp908/qc18bacc/r10b_snap
env QB_SB=400 QB_TD=0 QB_RD=0 QB_DPL_ARGS="-max_displacement 500" QB9_CHBLK=40 QB9_GPL2=1 QB_POSTCTS=0 QB9_GR_ITER=3 \
    QC_PNR_SET="QB_GPL_INCR_DENS 0.86" QC_PNR_THREADS=8 "$@" qc18bacc/impl/r10b/run.sh pnr $t \
    >> /tmp/ckp908/qc18bacc/build/$t.out 2>&1 < /dev/null
