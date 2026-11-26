#!/usr/bin/env bash
# One machine verdict of a block run (R92): every sign-off gate re-read from the run's own files, nothing re-run.
#   qc18bacc/flow/signoff/verdict.sh <run dir> [top]      top: the block of <run dir>/out/<top>_pg.v
# Output: one "GATE <name> <corner|-> PASS|FAIL <evidence>" line per gate, a VERDICT line naming the failed gates, and
# the last line "SIGNOFF <top> PASS|FAIL"; exit status 0 only on PASS.  Gates (signoff/verdict.py): per sign-off corner
# (common/env.sh qb_corners) the PrimeTime log evidence (qb_pt -check), every QB_PT_SIGNOFF count (setup, hold, max
# transition, max capacitance, clock max transition, noise, min pulse width, min period, coverage), the annotation
# split, the dont_use gate, the ETM (log, files, etmcheck) and the freshness chain netlist -> fill DEF -> SPEF -> PT ->
# ETM; for the block the ICC2 dont_use / ECO name-and-load / abstract gate lines of summary.txt, Calibre LVS / DRC (with
# the block deck's QB_ gate rules) / antenna (calibre/cal.sh check) and the chain GDS -> fill -> Calibre reports.
# The step driver calls it last; the result table of the paper is made from its GATE lines.
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../common/env.sh"
d=$(cd "${1:?run dir}" && pwd) || exit 1
top=${2:-$(basename "$(ls "$d"/out/*_pg.v 2> /dev/null | head -n 1)" _pg.v)}
[ -n "$top" ] || { echo "QB_FAIL verdict: no out/<top>_pg.v in $d"; echo "SIGNOFF ? FAIL"; exit 1; }
cs=$(qb_corners) || { echo "SIGNOFF $top FAIL"; exit 1; }
exec "$PY" -I "$here/verdict.py" "$d" "$top" "$QBF" $cs
