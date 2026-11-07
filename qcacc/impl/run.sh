#!/usr/bin/env bash
# DC / PrimeTime of the QC-GeMMX cluster with the flow and settings of the base kul_w4.2p run
# (impl/kulcluster/run.sh: DC 2024.09, kit WLM WireAreaLowkCon enclosed, same SDC, macros, PT ss / tt / ff), run on
# the build host from the repo root of a work tree with flow/, hw/tech/, impl/kulcluster, qcacc/impl and the QC
# synthesis pickle build/qcacc/generated/kulcluster_syn.sv (qcacc/hw/gen.sh).  Build root /tmp/$USER/qcacc_syn/build
# (macros: the base build's, KUL_MC_OUT default of impl/kulcluster/run.sh).
#   qcacc/impl/run.sh all [period] [tag]        syn + pt + summary   (default 4.2 qc_w4.2)
#   qcacc/impl/run.sh pt|summary <tag>
#   qcacc/impl/run.sh blocks <area.rpt> <out>  GeMMX block split (qcacc/impl/blocks.py) of any DC area report
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qcacc_syn/build}
export KUL_PICKLE=${KUL_PICKLE:-$ROOT/build/qcacc/generated/kulcluster_syn.sv}
K=$ROOT/impl/kulcluster
summ() { O=$ROOT/qcacc/results/impl_logs/$1; python3 -I "$K/summarize.py" "$QC_BUILD/syn/$1" "$O" &&
         python3 -I "$HERE/blocks.py" "$QC_BUILD/syn/$1/rpt/area.rpt" > "$O/blocks.txt"; }
cmd=${1:-}; shift || true
case "$cmd" in
all)     p=${1:-4.2}; t=${2:-qc_w$p}; "$K/run.sh" syn "$p" "$t" && "$K/run.sh" pt "$t" && summ "$t" ;;
pt)      "$K/run.sh" pt "$@" ;;
summary) summ "$1" ;;
blocks)  python3 -I "$HERE/blocks.py" "$1" > "$2" ;;
*)       sed -n '2,10p' "$0"; exit 1 ;;
esac
echo "QCACC_IMPL_DONE $cmd $*"
