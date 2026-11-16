#!/usr/bin/env bash
# R7e: DC (flow/tsmc65/syn/run_dc.sh, tt, wire-load) of wbs_top + wbs.sv, variants old | new (RSH) | a (RSH_A) | b (RSH_B):
#   qc18bacc/impl/r7e/dc.sh <variant> [period]     on tau, from the repository root; 1 core per run (QC_CORES=1)
set -eu
here=$(cd "$(dirname "$0")" && pwd); v=$1; p=${2:-1.65}
case $v in old) d="";; new) d="+define+RSH";; a) d="+define+RSH_A";; b) d="+define+RSH_B";; *) exit 1;; esac
f=${QC_BUILD:-/tmp/$USER/qc18bacc/build}/r7e; mkdir -p "$f"
printf '%s\n%s\n%s\n' "$d" "$here/wbs.sv" "$here/wbs_top.sv" | sed '/^$/d' > "$f/wbs_$v.f"
QC_CORES=${QC_CORES:-1} QC_CORNER=tt QC_PARAMS= "$here/../../../flow/tsmc65/syn/run_dc.sh" "$f/wbs_$v.f" wbs_top "$p" "r7e_wbs_$v"
