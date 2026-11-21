#!/usr/bin/env bash
# R45 minimal repro driver (tau6):  run45.sh <tag> <router-lef|kit> <nomincut-layers|none>
#   P&R of gen45.py's netlist with the base flow (r35 snapshot), then GDS (impl/r38/gds38.sh) + Calibre DRC (impl/r36/cal36.sh)
#   into $R45/build/{pnr,drc}/<tag>.  R45 = private NFS dir (default ~/r45).
set -u
R45=${R45:-$HOME/r45}; SNAP=${SNAP:-/tmp/ckp908/qc18bacc/r35_snap}
tag=$1; lef=$2; nm=$3
export R45 QC_BUILD=$R45/build R45_DIR=$R45/t45 QC_PNR_THREADS=${QC_PNR_THREADS:-8} QC_PNR_POST=0
[ "$lef" != kit ] && export R45_LEF=$lef
[ "$nm" = none ] && export R45_NOMINCUT="" || export R45_NOMINCUT="$nm"
"$SNAP/flow/tsmc65/pnr/run_pnr.sh" "$R45/t45.cfg" "$tag"
d=$QC_BUILD/pnr/$tag
grep -c "DRT-0073" $d/openroad.log | sed 's/^/R45 DRT-0073 count /'
grep "lef_pnr\|Number of violations\|Total wire length\|violation" $d/openroad.log | tail -4
QB38_MAPDIR=/tmp/ckp908/qc18bacc/build/drc/r38_map QC_BUILD=$QC_BUILD "$R45/repo/qc18bacc/impl/r38/gds38.sh" "$tag" "$d/out/t45.def" "$d/out/t45.gds" 2>&1 | tail -2
QB36_DRC_SED="-f $R45/repo/qc18bacc/impl/r38/drc_blk.sed" "$R45/repo/qc18bacc/impl/r36/cal36.sh" drc "$d/out/t45.gds" t45 "$QC_BUILD/drc/$tag" 8
