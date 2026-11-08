#!/bin/bash
# Queue driver: runs every CUDA_VISIBLE_DEVICES line of a sweep script, at most $J (default 3) at a time.
#   nohup qc18/ablate_driver.sh qc18/ablate.sh > /tmp/$USER/qc18/abl/driver.out 2>&1 &
# Kill rule: u2nofix is stopped after epoch 10 if its val is < 15 %.  Logs: <out>.log, driver.log.
cd "$(dirname "$0")/.."
S=$1 J=${J:-3}; O=/tmp/${USER:-$(whoami)}/qc18/abl; mkdir -p $O
eval "$(grep '^P=' $S)"
grep '^CUDA_VISIBLE_DEVICES' $S | while read -r line; do
  while [ "$(jobs -rp | wc -l)" -ge "$J" ]; do sleep 10; done
  out=$(eval echo "$line" | sed 's/.*--out //; s/ .*//'); name=$(basename $out)
  echo "START $name $(date +%T)" >> $O/driver.log
  ( eval "$line" > $out.log 2>&1; echo "END $name $(date +%T) rc=$?" >> $O/driver.log ) &
  if [[ $name == u2nofix* ]]; then
    ( while ! grep -q '^ep  10 ' $out.log 2>/dev/null; do sleep 15; pgrep -f "qc18.train.*$out" >/dev/null || exit; done
      v=$(grep '^ep  10 ' $out.log | sed 's/.* val *\([0-9.]*\).*/\1/')
      if awk "BEGIN{exit !($v < 15)}"; then pkill -f "qc18.train.*--out $out"; echo "KILLED $name ep10 val $v" >> $O/driver.log; fi ) &
  fi
  sleep 5
done
wait; echo "ALLDONE $(date +%T)" >> $O/driver.log
