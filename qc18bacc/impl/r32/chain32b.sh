#!/usr/bin/env bash
# R32 confirmation (parametric): chain32b.sh <src run> <new tag> <period> <L>: from <src>'s cts.odb with QB_IO_LAT <L>,
# else = R31 round 1 (prod -> dio -> dr), then PT tt (L) / tt (1.30) / ss (L), one at a time.
set -u
R=/tmp/ckp908/qc18bacc/r31_snap4/qc18bacc/impl/r31/run31.sh; P=/tmp/ckp908/qc18bacc/r31_snap4/qc18bacc/impl/r31/pt31.sh
B=/tmp/ckp908/qc18bacc/build; src=${1:?src}; tag=${2:?tag}; per=${3:?per}; export QB_IO_LAT=${4:?L}
echo R32_CHAIN_START $src $tag $per L $QB_IO_LAT $(date +%T)
if [ "${R32_SKIP_TO:-}" != pt ]; then
$R mk $tag $per $src || exit 1
cp $B/pnr/$src/db/cts.odb $B/pnr/$src/db/cts.sdc $B/pnr/$tag/db/
QB22_FROM=route $R prod $tag $per > $B/pnr/${tag}_prod.out 2>&1 || { echo R32_FAIL prod; exit 1; }
grep -h "postcts_hold_legal\|groute_tt" $B/pnr/$tag/summary.txt | cut -c1-140
$R dio $tag $per > $B/pnr/${tag}_dio.out 2>&1 || { echo R32_FAIL dio; exit 1; }
$R dr $tag $per > $B/pnr/${tag}_dr.out 2>&1 || { echo R32_FAIL dr; exit 1; }
grep -h "drc_violations" $B/pnr/$tag/summary.txt | tail -1
fi
export QB_PT_PERIOD=$per
$P $tag tt > $B/pnr/${tag}_pt_tt.out 2>&1; cp $B/pnr/$tag/r31_pt31_tt.log $B/pnr/$tag/r32_pt_tt_L.log; cp $B/pnr/$tag/rpt/r31_tt_worst.rpt $B/pnr/$tag/rpt/r32_tt_worst_L.rpt
QB_IO_LAT=1.30 $P $tag tt > $B/pnr/${tag}_pt_tt130.out 2>&1
$P $tag ss > $B/pnr/${tag}_pt_ss.out 2>&1
echo R32_CHAIN_DONE $(date +%T)
