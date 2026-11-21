#!/usr/bin/env bash
# R45: full re-route of a copy of the final act (r38_act_rr2 finish.odb) with the production GRT settings of
# impl/r38/hold38.sh (QB15_GADJ_L "M2-M3 0.6") and impl/r45/lef57db45.tcl (R45_NOFIX 1 = control), then GDS + Calibre DRC.
#   act45.sh <tag>      (tau6; outputs in $R45/build/{pnr,drc}/<tag>, R45 = private NFS dir)
set -u
R45=${R45:-$HOME/r45}; tag=$1; S=/tmp/ckp908/qc18bacc/build/pnr/r38_act_rr2; D=$R45/build/pnr/$tag
SNAP=/tmp/ckp908/qc18bacc/r35_snap
rm -rf "$D"; mkdir -p "$D/db" "$D/rpt"; cp "$S/config.tcl" "$S/kit.env" "$D/"; cp -r "$S/rc" "$D/"
cp "$S/db/finish.odb" "$S/db/finish.sdc" "$D/db/"
export QC_BUILD=$R45/build QB15_GADJ_L="M2-M3 0.6" QB38_RRDB=finish QB38_RR_MIN=1 QB35_THREADS=16 \
       R45_RR38=$R45/repo/qc18bacc/impl/r38/reroute38.tcl R45_FIXTCL=$R45/lef57db45.tcl
bash "$SNAP/qc18bacc/impl/r29/or29.sh" "$tag" "$R45/rr45.tcl" rr45.log
grep "R45_LEF57DB\|R38_RR" "$D/rr45.log.out"
QB38_MAPDIR=/tmp/ckp908/qc18bacc/build/drc/r38_map "$R45/repo/qc18bacc/impl/r38/gds38.sh" "$tag" "$D/out/qb_act2_blk.def" "$D/out/qb_act2_blk.gds" 2>&1 | tail -1
QB36_DRC_SED="-f $R45/repo/qc18bacc/impl/r38/drc_blk.sed" "$R45/repo/qc18bacc/impl/r36/cal36.sh" drc "$D/out/qb_act2_blk.gds" qb_act2_blk "$QC_BUILD/drc/$tag" 8
rm -f "$D/out/qb_act2_blk.gds"
echo ACT45_DONE
