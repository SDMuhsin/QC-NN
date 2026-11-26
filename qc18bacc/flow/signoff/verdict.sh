#!/usr/bin/env bash
# One machine verdict of a block run (R92): every sign-off gate re-read from the run's own files, nothing re-run.
#   qc18bacc/flow/signoff/verdict.sh <run dir> [top]      top: the block of <run dir>/out/<top>_pg.v
# Output: one "GATE <name> <corner|-> PASS|FAIL|MISSING <evidence>" line per gate, a VERDICT line naming the gates that
# did not pass, and the last line "SIGNOFF <top> PASS|FAIL"; exit status 0 only on PASS.  Gates (signoff/verdict.py): per
# sign-off corner (common/env.sh qb_corners) the PrimeTime log evidence (qb_pt -check), every QB_PT_SIGNOFF count (setup,
# hold, recovery, removal, max transition, max capacitance, clock max transition, min pulse width, min period, coverage;
# noise on the block's noise state with its driver-model counts and the act load pins), the chip top's clock latency
# file (= the session's QB_PT_LAT line), the annotation split, the dont_use gate, the ETM (log, files, etmcheck) and the
# freshness chain netlist -> fill DEF -> SPEF -> PT -> ETM; for the block the ICC2 gate lines of summary.txt (dont_use,
# floorplan tracks, place / cts legality, route gate, last ECO round's gate, ECO names and loads, abstract), Calibre LVS
# + its ERC (calibre/erc_allow.txt) / DRC (with the block deck's QB_ gate rules) / antenna (calibre/cal.sh check) and
# the chain GDS -> fill -> Calibre reports.  A gate whose evidence a run never produced is MISSING (it fails too).
# The step driver calls it last; the result table of the paper is made from its GATE lines.
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../common/env.sh"
d=$(cd "${1:?run dir}" && pwd) || exit 1
top=${2:-$(basename "$(ls "$d"/out/*_pg.v 2> /dev/null | head -n 1)" _pg.v)}
[ -n "$top" ] || { echo "QB_FAIL verdict: no out/<top>_pg.v in $d"; echo "SIGNOFF ? FAIL"; exit 1; }
cs=$(qb_corners) || { echo "SIGNOFF $top FAIL"; exit 1; }
exec "$PY" -I "$here/verdict.py" "$d" "$top" "$QBF" $cs
