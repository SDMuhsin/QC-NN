#!/usr/bin/env bash
# R30: sequential short-DR A/B variants on one run (dr30.tcl via impl/r29/or29.sh), one DR at a time (22 GB each).
#   qc18bacc/impl/r30/chain30.sh <tag> <db> <it> <label>=<R30_GADJ> [...]     (from the snapshot root)
set -u
here=$(cd "$(dirname "$0")" && pwd)
tag=$1; db=$2; it=$3; shift 3
for v in "$@"; do
  lab=${v%%=*}; adj=${v#*=}
  R30_DB=$db R30_IT=$it R30_THR=16 QB15_GADJ_L="${QB15_GADJ_L-M5-M9 0.10}" R30_GADJ="$adj" \
    "$here/../r29/or29.sh" "$tag" "$here/dr30.tcl" "r30x_$lab.log"
done
echo R30_CHAIN_DONE
