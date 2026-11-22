#!/usr/bin/env bash
# Synthesis / STA of the whole chip qb_chip (called by synth/run.sh chip; results/r4.md, r5b.md, r26.md): ARM macros of
# macros.txt (+ QB_MACROS_EXTRA lists) linked as .db black boxes, dont_touch; DC topographical tt; SDC chip_constraints.sdc,
# DC hook chip_dc_hook.tcl (column block ETMs: QB_EXTRA_DB_SS/TT/FF appended per corner), PT hook chip_pt_class.tcl.
#   qc18bacc/flow/synth/chip_dc.sh syn <top> <period> [tag]    DC (QC_TOPO default 1, QC_CORNER default tt)
#   qc18bacc/flow/synth/chip_dc.sh pt  <tag> [corner..]        PrimeTime
# QB_FL: file list.  QC_BUILD (default /tmp/$USER/qc18bacc/build), QC_CORES (default 16).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
FLOW=$ROOT/flow/tsmc65
. "$FLOW/site/sram.sh"
MC=$QC_MC_OUT
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}
export QC_SDC=$HERE/chip_constraints.sdc QC_HOOK=$HERE/chip_dc_hook.tcl QC_POST_HOOK=$HERE/chip_dc_post.tcl QC_PT_HOOK=$HERE/chip_pt_class.tcl QC_CLK=clk
export QC_CORES=${QC_CORES:-16} QC_CORNER=${QC_CORNER:-tt} QC_TOPO=${QC_TOPO:-1}
FL=${QB_FL:-$ROOT/qc18bacc/hw/tech/qb_chip_tech.f}
IFS=, read -r C_SS C_TT C_FF _ <<< "$QC_MC_CORNERS"
dbs() { sed 's/#.*//' "$HERE/macros.txt" ${QB_MACROS_EXTRA:-} | awk 'NF >= 5 { print $1 }' |
        while read -r i; do printf '%s ' "$MC/$i/${i}_$1_syn.db"; done; }
export QC_EXTRA_DB_SS="$(dbs "$C_SS")${QB_EXTRA_DB_SS:+ $QB_EXTRA_DB_SS}" QC_EXTRA_DB_TT="$(dbs "$C_TT")${QB_EXTRA_DB_TT:+ $QB_EXTRA_DB_TT}" QC_EXTRA_DB_FF="$(dbs "$C_FF")${QB_EXTRA_DB_FF:+ $QB_EXTRA_DB_FF}"
for f in $QC_EXTRA_DB_SS $QC_EXTRA_DB_TT $QC_EXTRA_DB_FF; do [ -f "$f" ] || { echo "missing macro view $f"; exit 1; }; done
cmd=${1:-}; shift || true
case "$cmd" in
syn) "$FLOW/syn/run_dc.sh" "$FL" "$1" "$2" "${3:-$1_${QC_CORNER}_p$2$([ "$QC_TOPO" = 1 ] && echo _topo)}" ;;
pt)  t=$1; shift; "$FLOW/sta/run_pt.sh" "$t" "${@:-tt ss}" ;;
*)   sed -n '2,7p' "$0"; exit 1 ;;
esac || { echo "QB_R4 FAIL $cmd $*"; exit 1; }
echo "QB_R4_DONE $cmd $*"
