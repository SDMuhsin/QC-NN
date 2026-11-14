#!/usr/bin/env bash
# Zero-delay gate-level check of the column block (results/r5a.md): tb_qb_core.sv -DQBC_COLARR on 8 abutted instances
# of the qb_col_blk netlist (hw/tb/qb_colarr.sv: act chained through the act_o feedthroughs), VCS + site cell models,
# vs the tile-level dataflow vectors of export_core.py.  On the build host from the repository root:
#   qc18bacc/impl/r5a/gls.sh <tag> <netlist.v> <imgdir> [imgdir ...]
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
tag=$1; nl=$2; shift 2
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}
w=$QC_BUILD/sim; mkdir -p "$w"
printf '%s\n' "$nl" "$root/qc18bacc/hw/tb/qb_colarr.sv" "$root/qc18bacc/hw/tb/tb_qb_core.sv" > "$w/r5a_$tag.f"
QC_GLS=1 QC_VCS_OPTS="+define+QBC_COLARR ${QB_VCS_OPTS:-}" QC_SIM_OPTS="+dir=$1" QC_PASS_RE="QB_CORE_TB.*PASS" \
  QC_FAIL_RE="FAIL|MISMATCH|Fatal|Error" "$root/flow/tsmc65/sim/run_vcs.sh" "r5a_$tag" tb_qb_core "$w/r5a_$tag.f"
shift
for d in "$@"; do ( cd "$w/r5a_$tag" && ./simv +dir="$d" > "sim_$(basename "$d").log" 2>&1; grep -E "QB_CORE_TB|MISMATCH" "sim_$(basename "$d").log" | head -4 ); done
