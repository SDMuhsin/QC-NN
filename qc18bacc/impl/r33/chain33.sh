#!/usr/bin/env bash
# R33 confirmation: run <tag> already holding db/grt.{odb,sdc} (r32_LB cts_rt + clumped-repeater collapse + GRT +
# post-GRT repair_timing + incremental GRT, coll33.tcl) -> R31 dio -> dr -> PT tt / ss at L 1.39 (as r32_LB)
set -u
R=/tmp/ckp908/qc18bacc/r31_snap4/qc18bacc/impl/r31/run31.sh; P=/tmp/ckp908/qc18bacc/r31_snap4/qc18bacc/impl/r31/pt31.sh
B=/tmp/ckp908/qc18bacc/build; tag=${1:?tag}; per=${2:?per}; export QB_IO_LAT=${3:?L}
echo R33_CHAIN_START $tag $per L $QB_IO_LAT $(date +%T)
$R dio $tag $per > $B/pnr/${tag}_dio.out 2>&1 || { echo R33_FAIL dio; exit 1; }
echo R33_DIO_DONE $(date +%T)
$R dr $tag $per > $B/pnr/${tag}_dr.out 2>&1 || { echo R33_FAIL dr; exit 1; }
grep -h "drc_violations" $B/pnr/$tag/summary.txt | tail -1; echo R33_DR_DONE $(date +%T)
export QB_PT_PERIOD=$per
$P $tag tt > $B/pnr/${tag}_pt_tt.out 2>&1
$P $tag ss > $B/pnr/${tag}_pt_ss.out 2>&1
echo R33_CHAIN_DONE $(date +%T)
