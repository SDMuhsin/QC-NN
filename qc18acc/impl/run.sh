#!/usr/bin/env bash
# DC / PrimeTime of QC18-ACC (top qa_top) on TSMC 65 nm tcbn65gplus with the flow and settings of impl/kulcluster
# (DC 2024.09 wire-load mode with the kit WLM WireAreaLowkCon enclosed (site.tcl QC_WLM_GROUP), PT ss / tt / ff
# pre-CTS ideal clocks), run on the build host from the host-local clone (/tmp/$USER/qc18acc/repo, git pull).
#   qc18acc/impl/run.sh macros                   flow/tsmc65/sram/mc_gen.sh gen qc18acc/impl/macros.txt (QC_MC_OUT)
#   qc18acc/impl/run.sh elab [period]            elaboration / link check (tag qa_elab)
#   qc18acc/impl/run.sh syn  <period> [tag]      DC, period in ns at ss (tag qa_w<period>)
#   qc18acc/impl/run.sh pt   <tag> [corner..]    PrimeTime ss / tt / ff (WNS, fmax, worst paths)
#   qc18acc/impl/run.sh summary <tag>            $QC_BUILD/syn/<tag>/res/{area,timing}.txt (summarize.py)
#   qc18acc/impl/run.sh all  <period> [tag]      syn + pt + summary
# RTL: hw/tech/qc18acc_tech.f (qa_sram on the macros of macros.txt, linked as .db black boxes, dont_touch).
# QC_BUILD: build root (default /tmp/$USER/qc18acc/build); QC_CORES (default 8).
# QA_V=3: the v3 design (Kb = 2): hw3/tech/qc18acc_tech.f and the macros of impl/v3/macros.txt (default QA_V=2: v2).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FLOW=$ROOT/flow/tsmc65
. "$FLOW/site/sram.sh"
MC=$QC_MC_OUT
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18acc/build}
export QC_SDC=$HERE/constraints.sdc QC_HOOK=$HERE/dc_hook.tcl QC_PT_HOOK=$HERE/pt_hook.tcl QC_CLK=clk
export QC_CORES=${QC_CORES:-8}
TOP=qa_top
FL=$ROOT/qc18acc/hw/tech/qc18acc_tech.f; MACROS=$HERE/macros.txt
if [ "${QA_V:-2}" = 3 ]; then FL=$ROOT/qc18acc/hw3/tech/qc18acc_tech.f; MACROS=$HERE/v3/macros.txt; fi

IFS=, read -r C_SS C_TT C_FF _ <<< "$QC_MC_CORNERS"
dbs() { sed 's/#.*//' "$MACROS" | awk 'NF >= 5 { print $1 }' |
        while read -r i; do printf '%s ' "$MC/$i/${i}_$1_syn.db"; done; }
export QC_EXTRA_DB_SS="$(dbs "$C_SS")" QC_EXTRA_DB_TT="$(dbs "$C_TT")" QC_EXTRA_DB_FF="$(dbs "$C_FF")"
check_dbs() {
    for f in $QC_EXTRA_DB_SS $QC_EXTRA_DB_TT $QC_EXTRA_DB_FF; do
        [ -f "$f" ] || { echo "missing macro view $f (qc18acc/impl/run.sh macros)"; exit 1; }
    done
}
syn() { check_dbs; "$FLOW/syn/run_dc.sh" "$FL" "$TOP" "$1" "$2"; }
summ() { python3 -I "$HERE/summarize.py" "$QC_BUILD/syn/$1" "$QC_BUILD/syn/$1/res"; }

cmd=${1:-}; shift || true
case "$cmd" in
macros)  "$FLOW/sram/mc_gen.sh" gen "$MACROS" ;;
elab)    QC_ELAB_ONLY=1 syn "${1:-3.5}" qa_elab ;;
syn)     p=$1; syn "$p" "${2:-qa_w$p}" ;;
pt)      check_dbs; t=$1; shift; "$FLOW/sta/run_pt.sh" "$t" "$@" ;;
summary) summ "$1" ;;
all)     p=$1; t=${2:-qa_w$p}
         syn "$p" "$t" && "$FLOW/sta/run_pt.sh" "$t" && summ "$t" ;;
*)       sed -n '2,13p' "$0"; exit 1 ;;
esac
echo "QA_IMPL_DONE $cmd $*"
