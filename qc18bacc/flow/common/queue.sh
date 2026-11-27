#!/usr/bin/env bash
# Detached step queue for one host: runs blocks/<blk>/run.sh steps in order, stops at the first failure.
#   qc18bacc/flow/common/queue.sh <logdir> <spec>     (detaches with setsid + nohup; prints the queue PID = its PGID)
# <spec>: one step per line, '#' comments:  <wait> [VAR=val ...] <blk> <step> <run> [args]
#   <wait>  '-' or comma-separated conditions, checked in order before the step starts:
#           pid:N            wait until process N has exited
#           file:PATH        wait until PATH exists (done-marker)
#           grep:PATH:PAT    wait until PATH contains PAT
#           need:PATH:PAT    fail the step at once unless PATH contains PAT (after a pid wait on a process outside
#                            this queue, whose exit status the queue cannot see; steps of one queue need no gate)
#   Fields are split on blanks (no globbing): write a blank in PAT as '.'.  VAR=val: env of that step only (QB50_MPA=1).
# Out: <logdir>/queue.state (one line per step: n blk step run status start end rc; status pending|wait|run|ok|fail),
#      <logdir>/q<n>_<blk>_<step>.out (step stdout + stderr), <logdir>/queue.log; <run dir>/queue.dir -> <logdir>
#      (read by common/status.sh; run dir = what "run.sh rundir <run>" prints for a block on the shared driver
#      common/block.sh, else $B/pnr/<run>).  rc = run.sh exit code: non-zero whenever a tool of the step failed (R53),
#      so the queue stops there.
# A spec problem fails at launch, before anything starts (qspec, R97; [M] tau11 r97xq: with a missing spec the launcher's
# cp failed, the queue started anyway and reported "QUEUE all done"): the spec is a readable file with at least one step
# line, and every step line parses: each wait condition one of the forms above, then VAR=val words, then <blk> <step>
# <run> with an executable blocks/<blk>/run.sh.  The detached queue checks its copy again.
set -uf
. "$(dirname "$0")/env.sh"
qspec() {   # qspec <spec>: one QUEUE_FAIL line per problem, non-zero if there is any
    local f=$1 l c n=0 m=0 bad=0 C
    [ -f "$f" ] && [ -r "$f" ] || { echo "QUEUE_FAIL spec $f: missing or unreadable"; return 1; }
    while IFS= read -r l || [ -n "$l" ]; do n=$((n + 1))
        [[ $l =~ ^[[:space:]]*(#|$) ]] && continue; m=$((m + 1)); set -- $l
        if [ "$1" != - ]; then
            [[ $1 =~ ^,|,,|,$ ]] && { echo "QUEUE_FAIL spec $f line $n: empty wait condition in '$1'"; bad=1; }
            IFS=, read -ra C <<< "$1"
            for c in "${C[@]}"; do
                [[ $c =~ ^(pid:[0-9]+|file:.+|(grep|need):[^:]+:.+)$ ]] || { echo "QUEUE_FAIL spec $f line $n: bad wait condition '$c'"; bad=1; }
            done
        fi; shift
        while [ $# -gt 0 ] && [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do shift; done
        if [ $# -lt 3 ]; then echo "QUEUE_FAIL spec $f line $n: no <blk> <step> <run> after the wait and VAR=val words"; bad=1
        elif [ ! -x "$QBF/blocks/$1/run.sh" ]; then echo "QUEUE_FAIL spec $f line $n: no executable blocks/$1/run.sh"; bad=1; fi
    done < "$f"
    [ $m -gt 0 ] || { echo "QUEUE_FAIL spec $f: no step line"; bad=1; }
    return $bad
}
lg=${1:?logdir}; spec=${2:?spec}
qspec "$spec" || exit 1
if [ "${QB_QUEUE_FG:-}" != 1 ]; then
    mkdir -p "$lg" && lg=$(cd "$lg" && pwd) && cp "$spec" "$lg/queue.spec" || { echo "QUEUE_FAIL cannot copy $spec to $lg"; exit 1; }
    QB_QUEUE_FG=1 setsid nohup "$0" "$lg" "$lg/queue.spec" > "$lg/queue.log" 2>&1 < /dev/null &
    echo "QUEUE pid/pgid $! log $lg"; exit 0
fi
st=$lg/queue.state; mapfile -t L < <(grep -v '^\s*\(#\|$\)' "$spec")
# run dir of <blk> <run> (R92: the column's is $B/icc2/col/<run>, where queue.dir never arrived)
rundir() { local s=$QBF/blocks/$1/run.sh; { grep -q 'common/block\.sh' "$s" 2> /dev/null && "$s" rundir "$2"; } || echo "$B/pnr/$2"; }
: > "$st"; n=0
for l in "${L[@]}"; do n=$((n + 1)); set -- $l; shift; while [[ $1 == *=* ]]; do shift; done
    echo "$n $1 $2 $3 pending - - -" >> "$st"; rd=$(rundir "$1" "$3"); mkdir -p "$rd"; echo "$lg" > "$rd/queue.dir"
done
put() { sed -i "${1}s/.*/$1 $2 $3 $4 $5 $6 $7 $8/" "$st"; }   # n blk step run status start end rc
now() { date +%s; }
n=0
for l in "${L[@]}"; do n=$((n + 1)); set -- $l; w=$1; shift; ev=()
    while [[ $1 == *=* ]]; do ev+=("$1"); shift; done
    blk=$1 step=$2 run=$3; shift 3; t0=$(now); put $n $blk $step $run wait $t0 - -; rc=0
    IFS=, read -ra C <<< "${w#-}"
    for c in "${C[@]}"; do k=${c%%:*} a=${c#*:}
        case $k in
        pid)  while kill -0 "$a" 2> /dev/null; do sleep 60; done ;;
        file) until [ -e "$a" ]; do sleep 60; done ;;
        grep) until grep -q "${a#*:}" "${a%%:*}" 2> /dev/null; do sleep 60; done ;;
        need) grep -q "${a#*:}" "${a%%:*}" 2> /dev/null || { echo "QUEUE need failed: $a"; rc=97; } ;;
        esac
    done
    if [ $rc = 0 ]; then t0=$(now); put $n $blk $step $run run $t0 - -; echo "QUEUE $n start $blk $step $run $(date +%T)"
        env "${ev[@]}" "$QBF/blocks/$blk/run.sh" "$step" "$run" "$@" > "$lg/q${n}_${blk}_$step.out" 2>&1 < /dev/null; rc=$?
    fi
    [ $rc = 0 ] && s=ok || s=fail; put $n $blk $step $run $s $t0 $(now) $rc; echo "QUEUE $n $s rc $rc $(date +%T)"
    [ $rc = 0 ] || { echo "QUEUE stopped at step $n"; exit $rc; }
done
echo "QUEUE all done $(date +%T)"
