#!/bin/bash
# R10b: partition of netlist r10_rpw (impl/r9b recipe) + structural equivalence, in $B/r10b_w
cd /tmp/ckp908/qc18bacc/r10b_snap
export QB_SYN=r10_rpw QB9_W=/tmp/ckp908/qc18bacc/build/r10b_ww
for s in dump part ports sdc equiv; do
    echo "== $s $(date +%T)"; qc18bacc/impl/r10b/run.sh $s || { echo "R10W_PART_FAIL $s"; exit 1; }
done
echo "R10W_PART_OK $(date +%T)"
