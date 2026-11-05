#!/usr/bin/env bash
# DC / PrimeTime of the KUL cluster (top KULCluster_snax_KUL_cluster_wrapper) on TSMC 65 nm tcbn65gplus, run on the
# build host from the repo root of a work tree that has flow/, hw/tech/, hw/kulcluster/generated/kulcluster_syn.sv
# and impl/kulcluster (sync.sh), and the macro views of impl/kulcluster/macros.txt (mc_gen.sh gen, host-local).
#   impl/kulcluster/run.sh macros                    flow/tsmc65/sram/mc_gen.sh gen impl/kulcluster/macros.txt
#   impl/kulcluster/run.sh elab [period]             elaboration / link check only (tag kul_elab)
#   impl/kulcluster/run.sh syn  [period] [tag]       DC, default 2.5 ns at ss (tag kul_p<period>)
#   impl/kulcluster/run.sh pt   <tag> [corner..]     PrimeTime ss / tt / ff (fmax, worst paths, vectorless power)
#   impl/kulcluster/run.sh summary <tag>             results/<tag>/*.txt
#   impl/kulcluster/run.sh all  [period] [tag]       syn + pt + summary
# KUL_MC_OUT: macro views (default /tmp/$USER/qcnn_kulsyn/macros; must match QC_MC_OUT of the site/sram.sh used to
# generate them).  QC_BUILD: build root (default /tmp/$USER/qcnn_kulsyn/build).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FLOW=$ROOT/flow/tsmc65
. "$FLOW/site/sram.sh"
MC=${KUL_MC_OUT:-/tmp/$USER/qcnn_kulsyn/macros}
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qcnn_kulsyn/build}
export QC_SDC=$HERE/constraints.sdc QC_HOOK=$HERE/dc_hook.tcl QC_PT_HOOK=$HERE/pt_hook.tcl QC_CLK=clu_clk
export QC_CORES=${QC_CORES:-8}
TOP=KULCluster_snax_KUL_cluster_wrapper
SRC=$QC_BUILD/src

IFS=, read -r C_SS C_TT C_FF _ <<< "$QC_MC_CORNERS"
dbs() { sed 's/#.*//' "$HERE/macros.txt" | awk 'NF >= 5 { print $1 }' |
        while read -r i; do printf '%s ' "$MC/$i/${i}_$1_syn.db"; done; }
export QC_EXTRA_DB_SS="$(dbs "$C_SS")" QC_EXTRA_DB_TT="$(dbs "$C_TT")" QC_EXTRA_DB_FF="$(dbs "$C_FF")"
check_dbs() {
    for f in $QC_EXTRA_DB_SS $QC_EXTRA_DB_TT $QC_EXTRA_DB_FF; do
        [ -f "$f" ] || { echo "missing macro view $f (impl/kulcluster/run.sh macros)"; exit 1; }
    done
}
syn() { check_dbs; "$HERE/gen_src.sh" "$SRC" && "$FLOW/syn/run_dc.sh" "$SRC/kul.f" "$TOP" "$1" "$2"; }

cmd=${1:-}; shift || true
case "$cmd" in
macros)  "$FLOW/sram/mc_gen.sh" gen "$HERE/macros.txt" ;;
elab)    QC_ELAB_ONLY=1 syn "${1:-2.5}" kul_elab ;;
syn)     p=${1:-2.5}; syn "$p" "${2:-kul_p$p}" ;;
pt)      check_dbs; t=$1; shift; "$FLOW/sta/run_pt.sh" "$t" "$@" ;;
summary) python3 -I "$HERE/summarize.py" "$QC_BUILD/syn/$1" "$HERE/results/$1" ;;
all)     p=${1:-2.5}; t=${2:-kul_p$p}
         syn "$p" "$t" && "$FLOW/sta/run_pt.sh" "$t" && python3 -I "$HERE/summarize.py" "$QC_BUILD/syn/$t" "$HERE/results/$t" ;;
*)       sed -n '2,13p' "$0"; exit 1 ;;
esac
echo "KUL_DONE $cmd $*"
