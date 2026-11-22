#!/usr/bin/env bash
# DC / PrimeTime of a macro-free top (block netlists; called by synth/run.sh): flow/tsmc65/syn/run_dc.sh (DC, kit WLM via
# site.tcl) + flow/tsmc65/sta/run_pt.sh (pre-CTS ideal clocks), SDC common/constraints.sdc, PT hook synth/pt_hook.tcl.
#   qc18bacc/flow/synth/dc.sh syn  <top> <period> [tag]     DC; compile corner QC_CORNER (default tt)
#   qc18bacc/flow/synth/dc.sh pt   <tag> [corner..]         PrimeTime (default tt ss)
#   qc18bacc/flow/synth/dc.sh all  <top> <period> [tag]     syn + pt tt ss
# QB_FL: file list; QC_HOOK / QC_TOPO / QC_COMPILE pass through to run_dc.sh.  QC_BUILD (default /tmp/$USER/qc18bacc/build); QC_CORES (default 8).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
FLOW=$ROOT/flow/tsmc65
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}
export QC_SDC=$HERE/../common/constraints.sdc QC_PT_HOOK=$HERE/pt_hook.tcl QC_CLK=clk
export QC_CORES=${QC_CORES:-8} QC_CORNER=${QC_CORNER:-tt}
FL=${QB_FL:-$ROOT/qc18bacc/hw/rtl/qb.f}     # QB_FL: other filelist, e.g. hw/rtl/qb_hb.f (results/pnr_pe.md)
cmd=${1:-}; shift || true
case "$cmd" in
syn) "$FLOW/syn/run_dc.sh" "$FL" "$1" "$2" "${3:-$1_${QC_CORNER}_p$2}" ;;
pt)  t=$1; shift; "$FLOW/sta/run_pt.sh" "$t" "${@:-tt ss}" ;;
all) t=${3:-$1_${QC_CORNER}_p$2}
     "$FLOW/syn/run_dc.sh" "$FL" "$1" "$2" "$t" && "$FLOW/sta/run_pt.sh" "$t" tt ss ;;
*)   sed -n '2,7p' "$0"; exit 1 ;;
esac
echo "QB_IMPL_DONE $cmd $*"
