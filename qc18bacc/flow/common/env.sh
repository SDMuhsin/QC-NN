# Sourced by every qc18bacc flow shell script (bash):
#   QBF   this flow (qc18bacc/flow)          ROOT  repository root (flow/tsmc65 = the shared OpenROAD / DC / PT flow)
#   B     build root QC_BUILD [/tmp/$USER/qc18bacc/build]; P&R runs in $B/pnr/<tag>
#   TOOLS QC_TOOLS [/tmp/$USER/tools]; PY / OR = its python3 / openroad
#   qb_kit  sources flow/tsmc65 common/tool.sh (FLOW, qc_tool) and exports QC_KIT, QC_PY
#   qb_pt   PrimeTime run + error check;  qb_wait  wait for background jobs, non-zero if one failed;  qb_icc2  ICC2 step (flow/icc2) in a run dir
QBF=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); ROOT=$(cd "$QBF/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; PY=$TOOLS/env/bin/python3; OR=$TOOLS/env/bin/openroad
qb_kit() {
    . "$ROOT/flow/tsmc65/common/tool.sh"
    QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY
}
# qb_pt <log> <command ...>: qc_tool of a PrimeTime run in the current dir; one PT_ERRORS line; non-zero unless the tool
# exited 0 and neither the log nor ./parasitics_command.log (read_parasitics, e.g. SPFP-103) has an '^Error' line
qb_pt() {
    local log=$1 rc e p=0; rm -f parasitics_command.log
    qc_tool "$@"; rc=$?
    e=$(grep -c '^Error' "$log"); [ -f parasitics_command.log ] && p=$(grep -c '^Error' parasitics_command.log)
    echo "PT_ERRORS $(basename "$log") rc $rc errors ${e:-NA} parasitics_errors $p"
    [ $rc = 0 ] && [ "$e" = 0 ] && [ "$p" = 0 ]
}
# qb_wait: wait for every background job of this shell; non-zero if any of them failed
qb_wait() { local j r=0; for j in $(jobs -p); do wait "$j" || r=1; done; return $r; }
# qb_icc2 <rundir> <step> [icc2_shell|icc2_lm_shell]: ICC2 step flow/icc2/<step>.tcl (Q-2019.12-SP2) in <rundir>, log
# <rundir>/<step>.log (+ .time); env QB_ICC2_CFG = block config.  One ICC2_STEP line; non-zero unless the tool exited 0,
# the log has the step's QB_ICC2_DONE marker and no '^Error' line.
ICC2_BIN=${QB_ICC2_BIN:-/CMC/tools/synopsys/icc2_vQ-2019.12-SP2/icc2/Q-2019.12-SP2/bin}
qb_icc2() {
    local d=$1 s=$2 sh=${3:-icc2_shell} log rc e
    . "$ROOT/flow/tsmc65/common/tool.sh"; mkdir -p "$d"; cd "$d" || return 1; log=$d/$s.log
    QB_ICC2_RUN=$d qc_tool "$log" "setenv LD_PRELOAD /lib64/libz.so.1; $ICC2_BIN/$sh -batch -f $QBF/icc2/$s.tcl"; rc=$?
    e=$(grep -c '^Error' "$log")
    echo "ICC2_STEP $s rc $rc errors $e done $(grep -c "^QB_ICC2_DONE $s" "$log") $(qc_time "$log")"
    [ $rc = 0 ] && [ "$e" = 0 ] && grep -q "^QB_ICC2_DONE $s" "$log"
}
