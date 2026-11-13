#!/usr/bin/env bash
# DC / PrimeTime of small macro-free tops of qc18bacc (hw/rtl/qb.f) on TSMC 65 nm tcbn65gplus, thin analogue of
# qc18acc/impl/run.sh: flow/tsmc65/syn/run_dc.sh (DC wire-load mode, kit WLM WireAreaLowkCon enclosed via site.tcl
# QC_WLM_GROUP) + flow/tsmc65/sta/run_pt.sh (pre-CTS ideal clocks), SDC impl/constraints.sdc, PT hook impl/pt_hook.tcl.
#   qc18bacc/impl/run.sh syn  <top> <period> [tag]     DC; compile corner QC_CORNER (default tt here)
#   qc18bacc/impl/run.sh pt   <tag> [corner..]         PrimeTime (default tt ss)
#   qc18bacc/impl/run.sh all  <top> <period> [tag]     syn + pt tt ss
# Tops: qb_pe_k8_a20 qb_pe_k16_a20 qb_pe_k32_a20 qb_pe_k16_a14 qb_lane_n qb_lane_w qb_lane_f* qb_core qb_core_s (impl/core_summary.py).  Default tag <top>_<corner>_p<period>.
# QC_BUILD: build root (default /tmp/$USER/qc18bacc/build); QC_CORES (default 8).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FLOW=$ROOT/flow/tsmc65
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}
export QC_SDC=$HERE/constraints.sdc QC_PT_HOOK=$HERE/pt_hook.tcl QC_CLK=clk
export QC_CORES=${QC_CORES:-8} QC_CORNER=${QC_CORNER:-tt}
FL=${QB_FL:-$ROOT/qc18bacc/hw/rtl/qb.f}     # QB_FL: other filelist, e.g. hw/rtl/qb_hb.f (results/pnr_pe.md)
cmd=${1:-}; shift || true
case "$cmd" in
syn) "$FLOW/syn/run_dc.sh" "$FL" "$1" "$2" "${3:-$1_${QC_CORNER}_p$2}" ;;
pt)  t=$1; shift; "$FLOW/sta/run_pt.sh" "$t" "${@:-tt ss}" ;;
all) t=${3:-$1_${QC_CORNER}_p$2}
     "$FLOW/syn/run_dc.sh" "$FL" "$1" "$2" "$t" && "$FLOW/sta/run_pt.sh" "$t" tt ss ;;
*)   sed -n '2,9p' "$0"; exit 1 ;;
esac
echo "QB_IMPL_DONE $cmd $*"
