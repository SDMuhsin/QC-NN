#!/usr/bin/env bash
# Design Compiler synthesis:   flow/tsmc65/syn/run_dc.sh <filelist.f> <top> <period_ns> [tag]
# Environment (all optional):
#   QC_CORNER   library corner ss | tt | ff                  (ss)
#   QC_TOPO     1 = topographical mode (Milkyway + TLU+ RC)  (0 = wire-load)
#   QC_WLM_GROUP / QC_WLM_MODE  wire-load selection group (site.tcl QC_WLM_GROUP) and mode (enclosed), QC_TOPO=0
#   QC_CLK      clock port name                              (clk)
#   QC_SDC      design SDC to use instead of the generated constraints (common/lib.tcl qc_constraints)
#   QC_IO_PCT   IO delay, % of the period                    (20)
#   QC_PARAMS   top-level parameters, DC syntax "W=8,N=4"
#   QC_HOOK     Tcl file sourced after link, before compile (design-specific DC settings)
#   QC_POST_HOOK Tcl file sourced after compile + change_names, before the outputs (optional)
#   QC_COMPILE  compile command  ("compile_ultra -no_autoungroup -gate_clock")
#   QC_EXTRA_DB_SS / _TT / _FF   extra link libraries (.db) per corner, e.g. SRAM macros (black boxes)
#   QC_CORES    max cores (8)     QC_BUILD  output root (<repo>/build/tsmc65)
# Output: $QC_BUILD/syn/<tag>/  (tag = <top>_<corner>_p<period>[_topo]): <top>.v .ddc .sdc [.spef], dc.log, rpt/,
#   summary.txt, run.env (read by sta/run_pt.sh).
set -u
. "$(dirname "$0")/../common/tool.sh"
[ $# -ge 3 ] || { sed -n '2,18p' "$0"; exit 1; }
flist=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); top=$2; period=$3
corner=${QC_CORNER:-ss}; topo=${QC_TOPO:-0}
tag=${4:-${top}_${corner}_p${period}$([ "$topo" = 1 ] && echo _topo)}
out=$BUILD/syn/$tag
rm -rf "$out"; mkdir -p "$out/rpt"
export QC_FLIST=$flist QC_TOP=$top QC_PERIOD=$period QC_CORNER=$corner QC_TOPO=$topo QC_OUT=$out
cat > "$out/run.env" <<EOT
QC_TOP=$top
QC_PERIOD=$period
QC_CLK=${QC_CLK:-clk}
QC_SDC=${QC_SDC:-}
QC_IO_PCT=${QC_IO_PCT:-20}
QC_TOPO=$topo
QC_WLM_GROUP=${QC_WLM_GROUP:-}
QC_WLM_MODE=${QC_WLM_MODE:-}
QC_EXTRA_DB_SS="${QC_EXTRA_DB_SS:-}"
QC_EXTRA_DB_TT="${QC_EXTRA_DB_TT:-}"
QC_EXTRA_DB_FF="${QC_EXTRA_DB_FF:-}"
EOT
mode=""; [ "$topo" = 1 ] && mode=-topographical_mode
cd "$out" || exit 1
# (PROC-3: DC helper process cannot connect back on some hosts; harmless, not counted)
qc_tool dc.log dc_shell $mode -f "$FLOW/syn/dc.tcl"
rc=$?
qc_time dc.log >> summary.txt 2>/dev/null
echo "DC_DONE $tag rc $rc errors $(grep '^Error' dc.log | grep -vc PROC-3) summary $([ -f "$top.v" ] && echo ok || echo FAIL)"
[ -f summary.txt ] && sed 's/^/  /' summary.txt
