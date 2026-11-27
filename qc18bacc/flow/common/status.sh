#!/usr/bin/env bash
# Status digest of P&R runs (at most 15 lines per run; grep / tail of the existing logs only).
#   qc18bacc/flow/common/status.sh <run_dir>...     (a run dir or <blk>/<tag> of $B/icc2)
# Per run: current step + elapsed (queue.state of the run's common/queue.sh queue, else the newest log),
# PT setup / hold / DRV / noise counts of every corner with a violator and the list of the clean
# corners (site.tcl sign-off corners, env.sh qb_corners; pt_blk_*.txt), the last ERROR line of the run's logs,
# the last ECO-loop round and route-gate line (out/eco/rounds.txt, summary.txt: common/block.sh, flow/icc2
# qb_route_close), and the run's queue.state lines.
set -uf
. "$(dirname "$0")/env.sh"
el() { local s=$(( $(date +%s) - $1 )); printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60)); }
for d in "$@"; do [ -d "$d" ] || d=$B/icc2/$d; r=$(basename "$d"); q=
  [ -f "$d/queue.dir" ] && q=$(cat "$d/queue.dir")/queue.state && [ -f "$q" ] || q=
  {
  echo "== $r ($(hostname -s) $(date +%T))"
  set +f; logs=$(ls -tr "$d"/*.log "$d"/*.out 2> /dev/null); set -f
  cur=$( [ -n "$q" ] && grep " $r \(wait\|run\) " "$q" | tail -n 1 )
  if [ -n "$cur" ]; then set -- $cur; echo "step $3 ($5, $(el $6))"
  else l=$(echo "$logs" | tail -n 1); [ -n "$l" ] && echo "newest log $(basename "$l") ($(el "$(stat -c %Y "$l")") ago)"; fi
  # (every grep of $logs reads /dev/null when the run has no logs: an empty file list would make grep read stdin)
  ok=
  for c in $(qb_corners); do set +f; p=$(ls -t "$d"/pt_*_"$c".txt 2> /dev/null | head -n 1); set -f; [ -n "$p" ] || continue
    x=$(grep -h '^all \|violating_endpoints\|^drv\|^signoff ' "$p" | grep -o '^all slack_ns [-0-9.]*\|[a-z_]*violating_endpoints [0-9]*\|[a-z_]*violators [0-9]*\|noise [0-9]*\|min_pulse_width [0-9]*\|min_period [0-9]*' \
      | tr '\n' ' ')
    if echo "$x" | grep -q '\(endpoints\|violators\|noise\|min_pulse_width\|min_period\) [1-9]'; then echo "PT $c $(echo "$x" | sed 's/_violating_endpoints//g; s/_violators//g')"; else ok="$ok $c"; fi
  done
  [ -n "$ok" ] && echo "PT no setup / hold / DRV / noise / pulse / period violator:$ok"
  e=$(grep -H 'ERROR\|^Error' $logs /dev/null 2> /dev/null | tail -n 1); [ -n "$e" ] && echo "last ${e#$d/}"
  [ -f "$d/out/eco/rounds.txt" ] && tail -n 1 "$d/out/eco/rounds.txt"
  [ -f "$d/summary.txt" ] && grep ' gate: ' "$d/summary.txt" | tail -n 1
  [ -n "$q" ] && grep " $r " "$q"
  } | cut -c1-170 | head -n 15
done
