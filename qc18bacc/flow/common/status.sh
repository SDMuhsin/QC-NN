#!/usr/bin/env bash
# Status digest of P&R runs (at most 15 lines per run; grep / tail of the existing logs only).
#   qc18bacc/flow/common/status.sh <run_dir>...     (run_dir = $B/pnr/<tag>, or a bare <tag>)
# Per run: current step + elapsed (queue.state of the run's common/queue.sh queue, else the newest log),
# latest DRT iteration + marker count, PT setup / hold / DRV per corner (pt_blk_* / pt_hub_* .txt), the last ERROR
# line of the run's logs, and the run's queue.state lines.
set -uf
. "$(dirname "$0")/env.sh"
el() { local s=$(( $(date +%s) - $1 )); printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60)); }
for d in "$@"; do [ -d "$d" ] || d=$B/pnr/$d; r=$(basename "$d"); q=
  [ -f "$d/queue.dir" ] && q=$(cat "$d/queue.dir")/queue.state && [ -f "$q" ] || q=
  {
  echo "== $r ($(hostname -s) $(date +%T))"
  set +f; logs=$(ls -tr "$d"/*.log "$d"/*.out 2> /dev/null); set -f
  cur=$( [ -n "$q" ] && grep " $r \(wait\|run\) " "$q" | tail -n 1 )
  if [ -n "$cur" ]; then set -- $cur; echo "step $3 ($5, $(el $6))"
  else l=$(echo "$logs" | tail -n 1); [ -n "$l" ] && echo "newest log $(basename "$l") ($(el "$(stat -c %Y "$l")") ago)"; fi
  dl=$(grep -l 'DRT-0195\]' $logs 2> /dev/null | tail -n 1)
  [ -n "$dl" ] && echo "DRT $(basename "$dl"): $(grep -o 'Start [0-9a-z]* [a-z]* iteration' "$dl" | tail -n 1)," \
    "markers $(grep 'DRT-0199\]' "$dl" | tail -n 1 | grep -o '[0-9]*\.$')"
  for c in tt ss ff; do set +f; p=$(ls -t "$d"/pt_*_"$c".txt 2> /dev/null | head -n 1); set -f; [ -n "$p" ] || continue
    echo "PT $c $(grep -h '^all \|violating_endpoints\|^drv' "$p" | grep -o '^all slack_ns [-0-9.]*\|[a-z]*_violating_endpoints [0-9]*\|max_[a-z]*_violators [0-9]*' \
      | tr '\n' ' ')"
  done
  e=$(grep -H 'ERROR\|^Error' $logs 2> /dev/null | tail -n 1); [ -n "$e" ] && echo "last ${e#$d/}"
  [ -n "$q" ] && grep " $r " "$q"
  } | cut -c1-170 | head -n 15
done
