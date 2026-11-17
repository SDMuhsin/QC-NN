#!/bin/bash
# R15 (results/r15.md): one hub floorplan variant with the R12 b450 flow (impl/r12/launch.sh env: r10_rpw, gpl, no srd,
# band-450 die, incremental gpl / gpl2 density 0.86 / 0.80, GRT 3 congestion iterations from place.odb) via impl/r15/run15.sh all.
# usage (on tau): launch.sh <tag> [env ...]   e.g. launch.sh r15_mid QB15_FP=mid ; densities: QC_PNR_SET="QB_GPL_INCR_DENS 0.80" QB9_GPL2_DENS=0.75
t=$1; shift
cd ${QB12_SNAP:-/tmp/ckp908/qc18bacc/r10b_snap}
B=/tmp/ckp908/qc18bacc/build
export QC_BUILD=$B QB_SYN=r10_rpw QB9_W=$B/r10b_ww QB10_SRD=0
env QB_SB=450 QB_TD=0 QB_RD=0 QB_DPL_ARGS="-max_displacement 500" QB9_CHBLK=40 QB9_GPL2=1 QB_POSTCTS=0 QB9_GR_ITER=3 \
    QC_PNR_SET="QB_GPL_INCR_DENS 0.86" QC_PNR_THREADS=${THR:-8} "$@" \
    qc18bacc/impl/r15/run15.sh all $t > $B/$t.out 2>&1 < /dev/null
