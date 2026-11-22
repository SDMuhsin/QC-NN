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
#      <logdir>/q<n>_<blk>_<step>.out (step stdout + stderr), <logdir>/queue.log; $B/pnr/<run>/queue.dir -> <logdir>
#      (read by common/status.sh).  rc = run.sh exit code: non-zero whenever a tool of the step failed (R53), so the
#      queue stops there.
set -uf
. "$(dirname "$0")/env.sh"
lg=${1:?logdir}; spec=${2:?spec}
if [ "${QB_QUEUE_FG:-}" != 1 ]; then
    mkdir -p "$lg"; lg=$(cd "$lg" && pwd); cp "$spec" "$lg/queue.spec"
    QB_QUEUE_FG=1 setsid nohup "$0" "$lg" "$lg/queue.spec" > "$lg/queue.log" 2>&1 < /dev/null &
    echo "QUEUE pid/pgid $! log $lg"; exit 0
fi
st=$lg/queue.state; mapfile -t L < <(grep -v '^\s*\(#\|$\)' "$spec")
: > "$st"; n=0
for l in "${L[@]}"; do n=$((n + 1)); set -- $l; shift; while [[ $1 == *=* ]]; do shift; done
    echo "$n $1 $2 $3 pending - - -" >> "$st"; mkdir -p "$B/pnr/$3"; echo "$lg" > "$B/pnr/$3/queue.dir"
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
        *)    echo "QUEUE bad wait $c"; rc=98 ;;
        esac
    done
    if [ $rc = 0 ]; then t0=$(now); put $n $blk $step $run run $t0 - -; echo "QUEUE $n start $blk $step $run $(date +%T)"
        env "${ev[@]}" "$QBF/blocks/$blk/run.sh" "$step" "$run" "$@" > "$lg/q${n}_${blk}_$step.out" 2>&1 < /dev/null; rc=$?
    fi
    [ $rc = 0 ] && s=ok || s=fail; put $n $blk $step $run $s $t0 $(now) $rc; echo "QUEUE $n $s rc $rc $(date +%T)"
    [ $rc = 0 ] || { echo "QUEUE stopped at step $n"; exit $rc; }
done
echo "QUEUE all done $(date +%T)"
