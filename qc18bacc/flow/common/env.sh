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
# Clock-network transition sign-off limit QC_CLK_TRAN_MAX (ns; R92, PI decision): the ONE limit every clock-network pin is
# signed off against (set_max_transition -clock_path: PrimeTime sign-off and ECO setup, signoff/pt/common.tcl
# qb_pt_clk_tran; ICC2 applies the same variable).  CTS builds to 0.15 ns (constraints.sdc clock transition: the
# guard-band); before, sign-off checked clock pins against the 0.5 ns data limit only (r91b ss [M]: worst 0.178 ns).
export QC_CLK_TRAN_MAX=${QC_CLK_TRAN_MAX:-0.25}
# Hold slack margin of the sign-off ECO QC_ECO_HOLD_MARGIN (ns; R92): read by signoff/pt/drv_eco.tcl.
export QC_ECO_HOLD_MARGIN=${QC_ECO_HOLD_MARGIN:-0.005}
# DRV / noise fix guard-bands of the sign-off ECO (fraction of the limit; R92, PI decision): drv_eco.tcl qb_eco_guard.
export QC_ECO_DRV_MARGIN=${QC_ECO_DRV_MARGIN:-0.02}
export QC_ECO_NOISE_MARGIN=${QC_ECO_NOISE_MARGIN:-0.02}
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
# Positive evidence (R92; before, the gate only looked for bad lines, so a log that lacked them passed): non-zero also
# unless <log> has PrimeTime's completion line "Thank you for using pt_shell!" (a killed / crashed session has none; a
# script error ends the script with an '^Error' line) and no error in its "Diagnostics summary", the annotated coupling
# count of the run's parasitics logs is > 0 (a run that read no coupled SPEF timed nothing with SI), and the DMSA
# scenario logs (worker_errors: out.log and parasitics logs in subdirs) have no '^Error' line either (an error in a
# worker alone used to pass: only <log> and its own parasitics log were counted).
# The PT_ERRORS line ends "signoff_fails N evidence ok|bad": evidence = everything but the QB_PT_SIGNOFF counts.
# qb_pt -check <log>: the same gate on the logs of a finished run, no tool run (signoff/verdict.py, which reads the
# evidence word; run it in the dir the run ran in): exit status and start time from qc_tool's <log>.time (rc NA
# without one, which fails).
qb_pt() {
    local log rc e p=0 x c k v t0 F W pl b we dn de chk=0 ev=bad
    if [ "$1" = -check ]; then chk=1; shift; fi
    log=$1; pl=${1%.log}_parasitics.log; b=$(basename "$pl")
    if [ $chk = 1 ]; then
        rc=$(sed -n 's/^[[:space:]]*Exit status: //p' "$log.time" 2> /dev/null); rc=${rc:-NA}
        t0=$(awk '/Elapsed/ {n = split($NF, a, ":"); for (i = 1; i <= n; i++) s = s * 60 + a[i]} END {printf "%d", s + 1}' "$log.time" 2> /dev/null)
        t0=$(( $(stat -c %Y "$log.time" 2> /dev/null || echo 0) - ${t0:-0} ))
    else
        rm -f "$pl" "$b"; t0=$(date +%s)
        QB_PT_PARA_LOG=$b qc_tool "$@"; rc=$?   # relative: DMSA scenario workers write theirs in their own work dirs
        if [ -f "$b" ] && ! [ "$b" -ef "$pl" ]; then mv "$b" "$pl"; fi
    fi
    e=$(grep -c '^Error' "$log"); [ -f "$pl" ] && p=$(grep -c '^Error' "$pl")
    W=$(find . -mindepth 2 -maxdepth 5 -name '*.nlib' -prune -o -type f \( -name "$b" -o -name parasitics_command.log \
        -o -name out.log \) -newermt "@$t0" -print)
    F="$W $([ -f "$pl" ] && echo "$pl")"
    we=$(cat $W /dev/null | grep -c '^Error')
    dn=$(grep -c '^Thank you for using pt_shell!' "$log"); de=$(grep -c '^Diagnostics summary:.* error' "$log")
    x=$(cat "$log" $F /dev/null | grep -c 'XTALK-011')
    c=$(cat $F /dev/null | grep -h 'Reduced coupling capacitances' | awk '{s += $NF; n++} END {printf "%d (%d lines)", s, n}')
    k=$(cat $F /dev/null | grep -h 'Annotated coupling capacitances' | awk '{s += $NF; n++} END {printf "%d (%d reads)", s, n}')
    v=$(grep -h '^QB_PT_SIGNOFF' "$log" | awk '{for (i = 3; i <= NF; i += 2) if ($i + 0) b++} END {print b + 0}')
    [ "$rc" = 0 ] && [ "$e" = 0 ] && [ "$p" = 0 ] && [ "$we" = 0 ] && [ "$x" = 0 ] && [ "${c%% *}" = 0 ] && [ "${k%% *}" -gt 0 ] \
        && [ "$dn" = 1 ] && [ "$de" = 0 ] && ev=ok
    echo "PT_ERRORS $(basename "$log") rc $rc errors ${e:-NA} parasitics_errors $p worker_errors $we xtalk011 $x reduced_coupling $c coupling_annotated $k completed $dn diagnostics_errors $de signoff_fails $v evidence $ev"
    [ $ev = ok ] && [ "$v" = 0 ]
}
# qb_corners: site.tcl QC_SIGNOFF_CORNERS (every sign-off corner: PrimeTime sign-off / DMSA ECO, ICC2 MCMM, the block ETMs
# and the chip top, R71), read from the corner table itself.  Non-zero with a QB_FAIL line on stderr when tclsh or
# site.tcl fails or the list is empty (R92: that was an empty list with status 0, so the post / views loops ran over no
# corner and the step ended DONE).  A command substitution in a for list hides the status, so callers assign first:
#   cs=$(qb_corners) || exit 1; for c in $cs; do ...
qb_corners() {
    local c
    c=$(QC_KIT=${QC_KIT:--} tclsh <<< "if {[catch {source $ROOT/flow/tsmc65/site/site.tcl} e]} { puts stderr \$e; exit 1 }; puts \$::QC_SIGNOFF_CORNERS") \
        && [ -n "${c//[[:space:]]/}" ] && { echo "$c"; return 0; }
    echo "QB_FAIL qb_corners: no sign-off corner from $ROOT/flow/tsmc65/site/site.tcl (tclsh / site.tcl error or empty QC_SIGNOFF_CORNERS)" >&2
    return 1
}
# qb_wait: wait for every background job of this shell; non-zero if any of them failed
qb_wait() { local j r=0; for j in $(jobs -p); do wait "$j" || r=1; done; return $r; }
# qb_icc2 <rundir> <step> [icc2_shell|icc2_lm_shell]: ICC2 step flow/icc2/<step>.tcl (Q-2019.12-SP2) in <rundir>, log
# <rundir>/<step>.log (+ .time); env QB_ICC2_CFG = block config.  One ICC2_STEP line; non-zero unless the tool exited 0,
# the log has the step's QB_ICC2_DONE marker and no '^Error' line, and the tool's own Error-message count is 0.
# That count (R92): the errors of a command run under redirect go to the variable / report file, not the log ([M]
# size_cell on a missing cell under redirect: 0 '^Error' log lines, get_message_info -error_count 2), so the step runs
# through <rundir>/<step>.run.tcl = the step script, then one QB_ICC2_MSG line with get_message_info -error_count.
ICC2_BIN=${QB_ICC2_BIN:-/CMC/tools/synopsys/icc2_vQ-2019.12-SP2/icc2/Q-2019.12-SP2/bin}
qb_icc2() {
    local d=$1 s=$2 sh=${3:-icc2_shell} log rc e m
    . "$ROOT/flow/tsmc65/common/tool.sh"; mkdir -p "$d"; cd "$d" || return 1; log=$d/$s.log
    printf 'source %s\nputs "QB_ICC2_MSG %s errors [get_message_info -error_count]"\n' "$QBF/icc2/$s.tcl" "$s" > "$d/$s.run.tcl"
    QB_ICC2_RUN=$d qc_tool "$log" "setenv LD_PRELOAD /lib64/libz.so.1; $ICC2_BIN/$sh -batch -f $d/$s.run.tcl"; rc=$?
    e=$(grep -c '^Error' "$log"); m=$(sed -n "s/^QB_ICC2_MSG $s errors //p" "$log" | tail -n 1)
    echo "ICC2_STEP $s rc $rc errors $e tool_errors ${m:-NA} done $(grep -c "^QB_ICC2_DONE $s" "$log") $(qc_time "$log")"
    [ $rc = 0 ] && [ "$e" = 0 ] && [ "$m" = 0 ] && grep -q "^QB_ICC2_DONE $s" "$log"
}
