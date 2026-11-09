#!/usr/bin/env bash
# P&R of QC18-ACC v2 on the build host (from the repository root of the host-local tree /tmp/$USER/qc18acc/repo):
#   qc18acc/pnr/run.sh pnr [tag]   OpenROAD (flow/tsmc65/pnr/run_pnr.sh qc18acc/pnr/qa.cfg) -> $QC_BUILD/pnr/<tag>
#   qc18acc/pnr/run.sh pt  [tag]   PrimeTime post-route timing with the def2spef SPEF (run_pt_post.sh), ss tt ff
# tag: qa_pnr.  QC_BUILD default /tmp/$USER/qc18acc/build (synthesis qa2_w3.3 under syn/), QC_PNR_THREADS 14.
# Env passes through to run_pnr.sh (QC_PNR_FROM / _TO / _SET / _POST) and macro_place.tcl (QA_BAND).
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18acc/build} QC_PNR_THREADS=${QC_PNR_THREADS:-14}
step=${1:-}; tag=${2:-qa_pnr}
case $step in
pnr) "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/qa.cfg" "$tag" ;;
pt)  "$root/flow/tsmc65/pnr/run_pt_post.sh" "$tag" ${QA_PT_CORNERS:-} ;;
*) sed -n '2,7p' "$0"; exit 1 ;;
esac
