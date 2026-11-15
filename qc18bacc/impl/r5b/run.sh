#!/usr/bin/env bash
# R5b full-chip P&R (results/r5b.md), on tau from the repository root of the host-local tree, QC_BUILD as R5a:
#   qc18bacc/impl/r5b/run.sh blk  <pnr tag of the block>   block views -> $QC_BUILD/r5b_blk: exact LEF + ETMs tt / ss / ff
#                                  (impl/r5a/post.sh abs etm), ring LEF (lef_ring.py), ETM copies with insertion arcs
#   qc18bacc/impl/r5b/run.sh syn                           top DC (gen.sh + impl/r4/run.sh syn, R4b recipe, R5e head,
#                                  core = 8 block ETMs), tag r5b_top (QB_SYN_TAG)
#   qc18bacc/impl/r5b/run.sh fp   <tag>                    P&R init, macro dump, mplace.py -> <run>/mplace.tcl
#   qc18bacc/impl/r5b/run.sh pnr  <tag>                    floorplan .. QC_PNR_TO (default finish) from the init checkpoint
#   qc18bacc/impl/r5b/run.sh pt   <tag> [corners]          SPEF (tt from the flow, ss via impl/pnr/run.sh spef) + PT pt_chip.tcl
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}
step=${1:?step}; tag=${2:-}
case $step in
blk) "$root/qc18bacc/impl/r5a/post.sh" "$tag" "abs etm"
     d=$B/pnr/$tag/out; mkdir -p "$B/r5b_blk"
     cp "$d/qb_col_blk.lef" "$d"/etm/qb_col_blk_{tt,ss,ff}{.lib,_lib.db} "$B/r5b_blk/"
     cd "$B/r5b_blk" && python3 -I "$here/lef_ring.py" qb_col_blk.lef qb_col_blk_ring.lef
     # insertion delays: max / min register clock latency of the routed block (results/r5d/pt_blk_r5dB_*.txt)
     python3 -I "$here/etm_ins.py" qb_col_blk_tt.lib qb_col_blk_tt_ins.lib ${QB_LAT_TT:-0.96 0.83}
     python3 -I "$here/etm_ins.py" qb_col_blk_ss.lib qb_col_blk_ss_ins.lib ${QB_LAT_SS:-1.47 1.24}
     python3 -I "$here/etm_ins.py" qb_col_blk_ff.lib qb_col_blk_ff_ins.lib ${QB_LAT_FF:-0.70 0.60} ;;
syn) "$here/gen.sh" "$B/r5b_gen"
     QB_HOOK=$here/dc_hook.tcl QB_SDC=$root/qc18bacc/impl/r4/constraints.sdc QB_FL=$B/r5b_gen/qb_chip_r5b.f QB_MACROS_EXTRA=$root/qc18bacc/impl/r5e/macros.txt \
     QB_EXTRA_DB_TT=$B/r5b_blk/qb_col_blk_tt_lib.db QB_EXTRA_DB_SS=$B/r5b_blk/qb_col_blk_ss_lib.db \
     QB_EXTRA_DB_FF=$B/r5b_blk/qb_col_blk_ff_lib.db "$root/qc18bacc/impl/r4/run.sh" syn qb_chip 1.65 ${QB_SYN_TAG:-r5b_top} ;;
fp)  QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" || exit 1
     ( cd "$B/pnr/$tag" && QB_RUN=$B/pnr/$tag "$TOOLS/env/bin/openroad" -no_init -no_splash -exit "$here/dump_macros.tcl" \
         > dump.log 2>&1 < /dev/null )
     python3 -I "$here/mplace.py" "$B/pnr/$tag/macros.txt" "$B/pnr/$tag/mplace.tcl" ;;
pnr) QC_PNR_FROM=${QC_PNR_FROM:-floorplan} "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" ;;
pt)  QB_SPEF_CORNERS=ss "$root/qc18bacc/impl/pnr/run.sh" spef "$tag"
     . "$root/flow/tsmc65/common/tool.sh"; dir=$B/pnr/$tag; . "$dir/kit.env"
     set -a; . "$(dirname "$NETLIST")/run.env"; set +a; cd "$dir" || exit 1
     export QC_SDC=$root/qc18bacc/impl/r4/constraints.sdc QC_PT_HOOK= QC_PERIOD=${QB_PT_PERIOD:-2.0}
     for c in ${3:-tt ss}; do
         QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c QB_BLK=$B/r5b_blk qc_tool "pt_chip_$c.log" pt_shell -f "$here/pt_chip.tcl"
         echo "PT_CHIP $c errors $(grep -c '^Error' pt_chip_$c.log)"; cat "pt_chip_$c.txt"
     done ;;
*) sed -n '2,11p' "$0"; exit 1 ;;
esac
echo "R5B_DONE $step $tag"
