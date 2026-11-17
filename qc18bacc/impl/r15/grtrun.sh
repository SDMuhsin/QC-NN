#!/bin/bash
# R15 GRT-only rerun of a placed R15 run (on tau): grtrun.sh <tag> <gtag> [env ...]
#   e.g. grtrun.sh r15_mid b3 QB_GI=3 QB15_GADJ_L="M5-M9 0.10"  -> run15.sh grt from db/place.odb + r10b ana + lay15 into grt_<gtag>
t=$1; g=$2; shift 2
cd ${QB12_SNAP:-/tmp/ckp908/qc18bacc/r10b_snap}
B=/tmp/ckp908/qc18bacc/build
export QC_BUILD=$B QB_SYN=r10_rpw QB9_W=$B/r10b_ww QB10_SRD=0
env QC_PNR_THREADS=${THR:-8} QB_GTAG=$g "$@" bash -c "
  echo R15G_START \$(date +%T)
  qc18bacc/impl/r15/run15.sh grt $t place || exit 1
  qc18bacc/impl/r10b/run.sh ana $t $g > /dev/null
  qc18bacc/impl/r15/run15.sh lay $t $g > /dev/null
  echo R15G_DONE \$(date +%T)" > $B/${t}_$g.out 2>&1 < /dev/null
