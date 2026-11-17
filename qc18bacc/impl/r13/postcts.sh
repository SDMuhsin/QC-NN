#!/usr/bin/env bash
# R13 (results/r13.md): post-CTS repair of a CTS checkpoint at the sign-off period (as r9a's r9a_f2r, rr.sh on tau):
#   impl/r13/postcts.sh <src tag> <tag>    copies <src>/db/cts.odb, cts.sdc with the period 1.85 -> QB_PNR_PERIOD_RT (2.0) into
#   pnr/<tag>, runs the flow's route step from there (QC_PNR_FROM=route) = PRE_ROUTE_TCL impl/r13/post_cts.tcl (S1 padding,
#   setup / hold repair, db/cts_rt.odb) and stops there (QB13_STOP_RT=1); routing follows with run.sh rt <tag> <tag2>.
set -u
here=$(cd "$(dirname "$0")" && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
src=${1:?src}; tag=${2:?tag}; per=${QB_PNR_PERIOD_RT:-2.0}; d=$B/pnr/$tag
rm -rf "$d"; mkdir -p "$d/db" "$d/rpt"
cd "$B/pnr/$src" && cp -r kit.env rc "$d/" && cp db/cts.odb "$d/db/" && grep -v postcts summary.txt > "$d/summary.txt"
half=$(awk -v p=$per 'BEGIN{print p/2}')
sed -E "s/(create_clock .*-period )[0-9.]+/\\1$per/; s/-waveform \\{0 [0-9.]+\\}/-waveform {0 $half}/" db/cts.sdc > "$d/db/cts.sdc"
grep -m1 create_clock "$d/db/cts.sdc"
QB13_STOP_RT=1 QC_PNR_FROM=route QB_PNR_PERIOD=$per "$here/run.sh" pnr "$tag"
ls -la "$d/db/cts_rt.odb" && echo R13_POSTCTS_DONE $tag
