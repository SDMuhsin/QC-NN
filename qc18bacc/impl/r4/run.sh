#!/usr/bin/env bash
# R4 synthesis / STA of the whole chip qb_chip (hw/tech/qb_chip_tech.f: QB_TECH, ARM macros of macros.txt linked as
# .db black boxes, dont_touch), DC topographical tt at the slice recipe (results/pnr_slice2.md: 1.65 ns, constraints
# impl/constraints.sdc, uncertainty 0.25 ns, IO 20 %), PT pre-route tt / ss on the DC parasitics + per-class paths.
#   qc18bacc/impl/r4/run.sh macros                    flow/tsmc65/sram/mc_gen.sh gen impl/r4/macros.txt
#   qc18bacc/impl/r4/run.sh syn  <top> <period> [tag] DC (QC_TOPO default 1, QC_CORNER default tt)
#   qc18bacc/impl/r4/run.sh pt   <tag> [corner..]     PrimeTime (pt_hook: fmax + pt_class.tcl classes)
# Tops: qb_chip (whole chip); per-hierarchy fallbacks: qb_head, qb_act2 (top-level params as in qb_top).
# QB_FL: other file list.  QC_BUILD (default /tmp/$USER/qc18bacc/build), QC_CORES (default 16).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
FLOW=$ROOT/flow/tsmc65
. "$FLOW/site/sram.sh"
MC=$QC_MC_OUT
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}
export QC_SDC=${QB_SDC:-$HERE/../constraints.sdc} QC_HOOK=$HERE/dc_hook.tcl QC_POST_HOOK=$HERE/dc_post.tcl QC_PT_HOOK=$HERE/pt_class.tcl QC_CLK=clk
export QC_CORES=${QC_CORES:-16} QC_CORNER=${QC_CORNER:-tt} QC_TOPO=${QC_TOPO:-1}
FL=${QB_FL:-$ROOT/qc18bacc/hw/tech/qb_chip_tech.f}
IFS=, read -r C_SS C_TT C_FF _ <<< "$QC_MC_CORNERS"
dbs() { sed 's/#.*//' "$HERE/macros.txt" | awk 'NF >= 5 { print $1 }' |
        while read -r i; do printf '%s ' "$MC/$i/${i}_$1_syn.db"; done; }
export QC_EXTRA_DB_SS="$(dbs "$C_SS")" QC_EXTRA_DB_TT="$(dbs "$C_TT")" QC_EXTRA_DB_FF="$(dbs "$C_FF")"
for f in $QC_EXTRA_DB_SS $QC_EXTRA_DB_TT $QC_EXTRA_DB_FF; do [ -f "$f" ] || { echo "missing macro view $f"; exit 1; }; done
cmd=${1:-}; shift || true
case "$cmd" in
macros) "$FLOW/sram/mc_gen.sh" gen "$HERE/macros.txt" ;;
syn) "$FLOW/syn/run_dc.sh" "$FL" "$1" "$2" "${3:-$1_${QC_CORNER}_p$2$([ "$QC_TOPO" = 1 ] && echo _topo)}" ;;
pt)  t=$1; shift; "$FLOW/sta/run_pt.sh" "$t" "${@:-tt ss}" ;;
*)   sed -n '2,9p' "$0"; exit 1 ;;
esac
echo "QB_R4_DONE $cmd $*"
