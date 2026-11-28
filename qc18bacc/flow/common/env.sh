# Sourced by every qc18bacc flow shell script (bash):
#   QBF   this flow (qc18bacc/flow)          ROOT  repository root (flow/tsmc65 = the shared kit / DC / PT flow)
#   B     build root QC_BUILD [/tmp/$USER/qc18bacc/build]; ICC2 P&R runs in $B/icc2/<blk>/<tag>
#   TOOLS QC_TOOLS [/tmp/$USER/tools]; PY = its python3
#   qb_kit  sources flow/tsmc65 common/tool.sh (FLOW, qc_tool) and exports QC_KIT;  QC_PY = PY (exported)
#   qb_pt   PrimeTime run + error check;  qb_wait  wait for background jobs, non-zero if one failed;  qb_icc2  ICC2 step (flow/icc2) in a run dir
#   qb_corners  the sign-off corner names of the one corner table, flow/tsmc65/site/site.tcl (R68)
#   qb_knobs    the flow knobs in force (QB_KNOBS, R103; below) and the Python tools' identity (qb_tools_id, R109)
QBF=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); ROOT=$(cd "$QBF/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; PY=$TOOLS/env/bin/python3
export QC_PY=$PY   # (the tools' Tcl runs flow Python through it: common/lib_cells.tcl qb_lib_tcq)
# (The act chain hold budget QC_ACT_HOLD_HUB, R81, is a sign-off limit of common/limits.txt since R107, read by both
# ends of the act chain through common/act_chain.tcl; it was exported here, and only the column read it.)
# Hold slack margin of the sign-off ECO QC_ECO_HOLD_MARGIN (ns; R92): read by signoff/pt/drv_eco.tcl.
export QC_ECO_HOLD_MARGIN=${QC_ECO_HOLD_MARGIN:-0.005}
# DRV / noise fix guard-bands of the sign-off ECO (fraction of the limit; R92, PI decision): drv_eco.tcl qb_eco_guard.
export QC_ECO_DRV_MARGIN=${QC_ECO_DRV_MARGIN:-0.02}
export QC_ECO_NOISE_MARGIN=${QC_ECO_NOISE_MARGIN:-0.02}
# ECO loop rounds (common/block.sh blk_eco), ICC2 cores (icc2/common.tcl), PrimeTime DMSA ECO cores per scenario
# (signoff/pt/drv_eco.tcl): their one default (R103; each was a default of its reader); the regression block's .env
# sets its own QB_ICC2_CORES default (1, R110) before this file
export QC_ECO_ROUNDS=${QC_ECO_ROUNDS:-4} QB_ICC2_CORES=${QB_ICC2_CORES:-16} QB_ECO_CORES=${QB_ECO_CORES:-4}
# Flow knobs (R103): every environment setting a block step reads that changes what it does (the P&R guard-bands of the
# block .env, the ECO margins / rounds / modes above, pnr range, cores, ICC2 binary and label, LVS deck extras), the
# sign-off limits (common/limits.txt names) and any QC_EXTRA_DB_<corner>.  qb_knobs prints " <name>=<value in force>"
# for each (<unset> when not set); common/block.sh logs them as the BLK_KNOBS line of every step, and common/regress.sh
# check fails unless every step's equal the snapshot's committed defaults (run.sh knobs in an empty environment) and
# the reference's.  (Hunt round 8 on 5fdd167: these came from the environment and nothing checked them; a queue
# VAR=val word or a login-shell export changed the regression run unseen.)
# qb_knobs <name> ...: the caller's further knobs too (common/block.sh: the Calibre deck edits BLK_*_SED).  A value is
# printed as one word (qb_knob): the flow root as <flow>, blanks as ',' (R104: a run's line is compared across snapshots),
# an empty value as <unset> (R113; hunt round 14: an empty value was "<name>=" here and <unset> in signoff/calibre/cal.sh's
# deck edit record, so a block's empty BLK_*_SED failed the verdict's deck gate against its own committed defaults)
QB_KNOBS="QC_PNR_GUARD_HOLD QC_PNR_GUARD_TRAN QC_PNR_FROM QC_PNR_TO QC_ECO_ROUNDS QC_ECO_HOLD_MARGIN QC_ECO_DRV_MARGIN
    QC_ECO_NOISE_MARGIN QC_ECO_OVERRIDE_STOP QC_ECO_PT_ONLY QB_ICC2_CORES QB_ECO_CORES QB_ICC2_BIN QB_ICC2_LABEL
    QB36_LVS_EXTRA QB36_HCELL"
qb_knob() { local v=${!1:-<unset>}; v=${v//"$QBF"/<flow>}; printf '%s=%s' "$1" "${v//[[:space:]]/,}"; }   # qb_knob <name>: "<name>=<word>"
qb_knobs() {
    local k
    for k in $QB_KNOBS "$@" $(awk '{ sub(/#.*/, "") } NF { print $1 }' "$QBF/common/limits.txt") $(compgen -v QC_EXTRA_DB_); do
        printf ' %s' "$(qb_knob "$k")"
    done
    qb_tools_id
}
# The Python tools of the flow (R109; hunt round 12: QC_TOOLS was recorded nowhere, so a run on another tools tree looked
# the same): " QC_TOOLS=<path in force (TOOLS)> QB_TOOLS_PYTHON=<python version of its env> QB_TOOLS_KLAYOUT=<klayout
# module version of its kl_py>" (none when one does not run), on every BLK_KNOBS line, so in the regression reference
qb_tools_id() {
    local p k
    p=$("$PY" -I -c 'import platform; print(platform.python_version())' 2> /dev/null) || p=
    k=$(PYTHONPATH=$TOOLS/kl_py "$PY" -c 'import klayout.db as d; print(d.__version__)' 2> /dev/null) || k=
    printf ' QC_TOOLS=%s QB_TOOLS_PYTHON=%s QB_TOOLS_KLAYOUT=%s' "${TOOLS//[[:space:]]/,}" "${p:-none}" "${k:-none}"
}
# qb_committed_knobs <blk> <tag>: the BLK_KNOBS line of blocks/<blk>/run.sh knobs in an empty environment = the committed
# defaults of the block's flow knobs (common/regress.sh check; signoff/verdict.sh: the Calibre deck edit gates, R106)
qb_committed_knobs() { env -i HOME="$HOME" USER="$USER" PATH="$PATH" "$QBF/blocks/$1/run.sh" knobs "$2" 2>&1 | grep -m 1 '^BLK_KNOBS '; }
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
# <log> (noise, min pulse width, min period violators), and on any count that is not an integer (qb_pt_signoff_fails, R109).
# Positive evidence (R92; before, the gate only looked for bad lines, so a log that lacked them passed): non-zero also
# unless <log> has PrimeTime's completion line "Thank you for using pt_shell!" (a killed / crashed session has none; a
# script error ends the script with an '^Error' line) and no error in its "Diagnostics summary", the annotated coupling
# count of the run's parasitics logs is > 0 (a run that read no coupled SPEF timed nothing with SI), and the DMSA
# scenario logs (worker_errors: out.log and parasitics logs in subdirs) have no '^Error' line either (an error in a
# worker alone used to pass: only <log> and its own parasitics log were counted).
# The scenario logs are the session's own (R97; before, any out.log / parasitics log under the run dir newer than the
# session's start counted, so a later ECO round's workers added errors or coupling counts to an older session's
# evidence): only those in the DMSA work dir the session names in its log (QB_PT_WORKDIR line, signoff/pt/drv_eco.tcl;
# a session without one has no scenario logs) and written between its start and its end.
# Errors of a command run under redirect (the report counts of signoff/pt/common.tcl) ARE counted, by diagnostics_errors:
# their message goes to the redirect variable / file, not the log, but PrimeTime's exit line "Diagnostics summary: N
# errors" counts them.  [M] R100: that line counted 9 errors against 4 visible '^Error' log lines, = get_message_info
# -error_count; [M] R104 tau14, a seeded report_timing -from <no such pin> + report_constraint without a design, both
# under redirect + catch: 0 '^Error' log lines, 2 in the redirect variables, error_count 2, "Diagnostics summary: 2
# errors" -> diagnostics_errors 1, evidence bad (the same script without them: diagnostics_errors 0).
# The PT_ERRORS line ends "signoff_fails N evidence ok|bad": evidence = everything but the QB_PT_SIGNOFF counts.
# qb_pt -check <log>: the same gate on the logs of a finished run, no tool run (signoff/verdict.py, which reads the
# evidence word; run it in the dir the run ran in): exit status, start and end time from qc_tool's <log>.time (rc NA
# without one, which fails).
qb_pt() {
    local log rc e p=0 x c k v t0 t1 F W wd pl b we dn de chk=0 ev=bad
    if [ "$1" = -check ]; then chk=1; shift; fi
    log=$1; pl=${1%.log}_parasitics.log; b=$(basename "$pl")
    if [ $chk = 1 ]; then
        rc=$(sed -n 's/^[[:space:]]*Exit status: //p' "$log.time" 2> /dev/null); rc=${rc:-NA}
        t0=$(awk '/Elapsed/ {n = split($NF, a, ":"); for (i = 1; i <= n; i++) s = s * 60 + a[i]} END {printf "%d", s + 1}' "$log.time" 2> /dev/null)
        t1=$(( $(stat -c %Y "$log.time" 2> /dev/null || echo 0) + 1 )); t0=$(( t1 - 1 - ${t0:-0} ))
    else
        rm -f "$pl" "$b"; t0=$(date +%s)
        QB_PT_PARA_LOG=$b qc_tool "$@"; rc=$?   # relative: DMSA scenario workers write theirs in their own work dirs
        t1=$(( $(date +%s) + 1 ))
        if [ -f "$b" ] && ! [ "$b" -ef "$pl" ]; then mv "$b" "$pl"; fi
    fi
    e=$(grep -c '^Error' "$log"); [ -f "$pl" ] && p=$(grep -c '^Error' "$pl")
    wd=$(sed -n 's/^QB_PT_WORKDIR //p' "$log" | tail -n 1)
    W=$([ -n "$wd" ] && [ -d "$wd" ] && find "$wd" -mindepth 1 -maxdepth 3 -type f \( -name "$b" -o -name parasitics_command.log \
        -o -name out.log \) -newermt "@$t0" ! -newermt "@$t1" -print)
    F="$W $([ -f "$pl" ] && echo "$pl")"
    we=$(cat $W /dev/null | grep -c '^Error')
    dn=$(grep -c '^Thank you for using pt_shell!' "$log"); de=$(grep -c '^Diagnostics summary:.* error' "$log")
    x=$(cat "$log" $F /dev/null | grep -c 'XTALK-011')
    c=$(cat $F /dev/null | grep -h 'Reduced coupling capacitances' | awk '{s += $NF; n++} END {printf "%d (%d lines)", s, n}')
    k=$(cat $F /dev/null | grep -h 'Annotated coupling capacitances' | awk '{s += $NF; n++} END {printf "%d (%d reads)", s, n}')
    v=$(grep -h '^QB_PT_SIGNOFF' "$log" | qb_pt_signoff_fails)
    [ "$rc" = 0 ] && [ "$e" = 0 ] && [ "$p" = 0 ] && [ "$we" = 0 ] && [ "$x" = 0 ] && [ "${c%% *}" = 0 ] && [ "${k%% *}" -gt 0 ] \
        && [ "$dn" = 1 ] && [ "$de" = 0 ] && ev=ok
    echo "PT_ERRORS $(basename "$log") rc $rc errors ${e:-NA} parasitics_errors $p worker_errors $we xtalk011 $x reduced_coupling $c coupling_annotated $k completed $dn diagnostics_errors $de signoff_fails $v evidence $ev"
    [ $ev = ok ] && [ "$v" = 0 ]
}
# qb_pt_signoff_fails: QB_PT_SIGNOFF lines on stdin ("QB_PT_SIGNOFF <key> <count> ..."); prints how many counts fail: a
# count that is not an integer (R109; hunt round 12: "$i + 0" made a non-numeric count, e.g. NA or a missing value, 0 =
# pass) or not 0; and one per line that is not key / count pairs
qb_pt_signoff_fails() {
    awk '{ if (NF < 3 || NF % 2 == 0) b++; for (i = 3; i <= NF; i += 2) if ($i !~ /^-?[0-9]+$/ || $i + 0 != 0) b++ } END { print b + 0 }'
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
# qb_icc2 -check <rundir> <step>: the same gate on the log of a finished step, no tool run (signoff/verdict.py icc2_log:
# every ICC2 step of out/'s label chain, R111; R106: its abstract_log gate read only the done marker and the '^Error'
# lines; common/block.sh: the route step before a pnr range from outputs): the exit status from qc_tool's <log>.time
# (rc NA without one, which fails).
# The completion record (R113; hunt round 14 on f9f2580: nothing recorded the order the steps finished in, so a partial
# re-run place .. cts followed by a pnr range from outputs signed off the route label of the layout before): a step that
# passes appends "icc2_done <step> <label> <epoch>" to <rundir>/summary.txt, <label> from the log's last QB_ICC2_DONE
# marker ("QB_ICC2_DONE <label>" or "QB_ICC2_DONE <step> label <label>").  summary.txt is append-only, so the line order
# is the order of completion, read from the content alone (a copied run dir keeps it, its mtimes need not):
# common/block.sh blk_done_order (the pnr range from outputs; signoff/verdict.py step_order).
ICC2_BIN=${QB_ICC2_BIN:-/CMC/tools/synopsys/icc2_vQ-2019.12-SP2/icc2/Q-2019.12-SP2/bin}
qb_icc2() {
    local d s sh log rc e m n chk=0
    if [ "$1" = -check ]; then chk=1; shift; fi
    d=$1 s=$2 sh=${3:-icc2_shell}; log=$d/$s.log
    . "$ROOT/flow/tsmc65/common/tool.sh"
    if [ $chk = 1 ]; then
        rc=$(sed -n 's/^[[:space:]]*Exit status: //p' "$log.time" 2> /dev/null); rc=${rc:-NA}
    else
        mkdir -p "$d"; cd "$d" || return 1
        printf 'source %s\nputs "QB_ICC2_MSG %s errors [get_message_info -error_count]"\n' "$QBF/icc2/$s.tcl" "$s" > "$d/$s.run.tcl"
        QB_ICC2_RUN=$d qc_tool "$log" "setenv LD_PRELOAD /lib64/libz.so.1; $ICC2_BIN/$sh -batch -f $d/$s.run.tcl"; rc=$?
    fi
    e=$(grep -c '^Error' "$log" 2> /dev/null); m=$(sed -n "s/^QB_ICC2_MSG $s errors //p" "$log" 2> /dev/null | tail -n 1)
    n=$(grep -c "^QB_ICC2_DONE $s" "$log" 2> /dev/null)
    echo "ICC2_STEP $s rc $rc errors ${e:-NA} tool_errors ${m:-NA} done ${n:-0} $(qc_time "$log")"
    [ "$rc" = 0 ] && [ "$e" = 0 ] && [ "$m" = 0 ] && [ "${n:-0}" -gt 0 ] || return 1
    [ $chk = 1 ] || awk -v s="$s" -v t="$(date +%s)" '$1 == "QB_ICC2_DONE" { l = ($3 == "label" ? $4 : $2) }
        END { if (l == "") exit 1; print "icc2_done", s, l, t }' "$log" >> "$d/summary.txt"
}
