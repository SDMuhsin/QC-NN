# Sourced by every qc18bacc flow shell script (bash):
#   QBF   this flow (qc18bacc/flow)          ROOT  repository root (flow/tsmc65 = the shared OpenROAD / DC / PT flow)
#   B     build root QC_BUILD [/tmp/$USER/qc18bacc/build]; P&R runs in $B/pnr/<tag>
#   TOOLS QC_TOOLS [/tmp/$USER/tools]; PY / OR = its python3 / openroad
#   qb_kit  sources flow/tsmc65 common/tool.sh (FLOW, qc_tool) and exports QC_KIT;  QC_PY = PY (exported)
#   qb_pt   PrimeTime run + error check;  qb_wait  wait for background jobs, non-zero if one failed;  qb_icc2  ICC2 step (flow/icc2) in a run dir
#   qb_corners  the sign-off corner names of the one corner table, flow/tsmc65/site/site.tcl (R68)
QBF=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); ROOT=$(cd "$QBF/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; PY=$TOOLS/env/bin/python3; OR=$TOOLS/env/bin/openroad
export QC_PY=$PY   # (the tools' Tcl runs flow Python through it: common/lib_cells.tcl qb_lib_tcq, qb.tcl)
# act chain hold budget QC_ACT_HOLD_HUB (ns; R81, PI decision): the one value both ends of the act chain read.  act is a
# 7-deep point-to-point chain hub -> col 0 -> act_o -> col 1 -> ...; every column is the same macro and column c gets
# act at column c-1's arrival + its feedthrough, so the minimum arrival at any column's act input is the hub's
# guaranteed minimum.  The hold budget is therefore allocated ONCE, to the act source: the column's act input -min =
# qb5_hold_min + QC_ACT_HOLD_HUB (blocks/col/io_budget.tcl qb5_act_in_min; act_o -min follows through qb5_act_o_min),
# the hub's act output -min = -QC_ACT_HOLD_HUB (blocks/hub/sdc.py).  Basis: R80 [M] act -> u_pe hold demand 0.066-0.070 ns
# at ff / ml plus a derate spread up to 0.074 ns -> 0.10 ns.  (R80 [M]: without it the column-0 launch bound was applied
# to all 8 columns, 18042 hold buffers in u_pe.)  Exported: the ICC2 / PrimeTime Tcl and the hub's Python read it.
export QC_ACT_HOLD_HUB=0.10
qb_kit() {
    . "$ROOT/flow/tsmc65/common/tool.sh"
    QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT
}
# qb_pt <log> <command ...>: qc_tool of a PrimeTime run in the current dir; one PT_ERRORS line; non-zero unless the tool
# exited 0 and neither the log nor its parasitics log (read_parasitics side process, e.g. SPFP-103) has an '^Error' line.
# The parasitics log is <log>_parasitics.log (QB_PT_PARA_LOG, set by signoff/pt/common.tcl qb_pt_spef as PT's
# parasitics_log_file; R75): one file per run, so PT runs sharing a dir (top corners in parallel) never overwrite each
# other's (R74 lost wcl_rcw's through the shared ./parasitics_command.log).
# SI gate (R64, signoff/pt/common.tcl qb_pt_spef): also non-zero on any XTALK-011 (SI on, no SI data) or a non-zero
# "Reduced coupling capacitances" count in the logs this run wrote: <log>, its parasitics log, and the DMSA scenario
# logs (out.log and parasitics logs in subdirs); PT prints the reduced line only when it grounds coupling, the
# kept count is "Annotated coupling capacitances" (logged).
# Sign-off gate (R67, signoff/pt/common.tcl qb_pt_si_checks; R68 col_blk.tcl: setup / hold / DRV): non-zero on any non-zero count of a QB_PT_SIGNOFF line of
# <log> (noise, min pulse width, min period violators).
qb_pt() {
    local log=$1 rc e p=0 x c k v t0 F pl b; pl=${1%.log}_parasitics.log; b=$(basename "$pl"); rm -f "$pl" "$b"; t0=$(date +%s)
    QB_PT_PARA_LOG=$b qc_tool "$@"; rc=$?   # relative: DMSA scenario workers write theirs in their own work dirs
    if [ -f "$b" ] && ! [ "$b" -ef "$pl" ]; then mv "$b" "$pl"; fi
    e=$(grep -c '^Error' "$log"); [ -f "$pl" ] && p=$(grep -c '^Error' "$pl")
    F=$(find . -mindepth 2 -maxdepth 5 -name '*.nlib' -prune -o -type f \( -name "$b" -o -name parasitics_command.log \
        -o -name out.log \) -newermt "@$t0" -print; [ -f "$pl" ] && echo "$pl")
    x=$(cat "$log" $F /dev/null | grep -c 'XTALK-011')
    c=$(cat $F /dev/null | grep -h 'Reduced coupling capacitances' | awk '{s += $NF; n++} END {printf "%d (%d lines)", s, n}')
    k=$(cat $F /dev/null | grep -h 'Annotated coupling capacitances' | awk '{s += $NF; n++} END {printf "%d (%d reads)", s, n}')
    v=$(grep -h '^QB_PT_SIGNOFF' "$log" | awk '{for (i = 3; i <= NF; i += 2) if ($i + 0) b++} END {print b + 0}')
    echo "PT_ERRORS $(basename "$log") rc $rc errors ${e:-NA} parasitics_errors $p xtalk011 $x reduced_coupling $c coupling_annotated $k signoff_fails $v"
    [ $rc = 0 ] && [ "$e" = 0 ] && [ "$p" = 0 ] && [ "$x" = 0 ] && [ "${c%% *}" = 0 ] && [ "$v" = 0 ]
}
# qb_corners: site.tcl QC_SIGNOFF_CORNERS (every sign-off corner: PrimeTime sign-off / DMSA ECO, ICC2 MCMM, the block ETMs
# and the chip top, R71), read from the corner table itself
qb_corners() { QC_KIT=${QC_KIT:--} tclsh <<< "source $ROOT/flow/tsmc65/site/site.tcl; puts \$::QC_SIGNOFF_CORNERS"; }
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
