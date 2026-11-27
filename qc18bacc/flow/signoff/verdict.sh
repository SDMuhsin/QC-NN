#!/usr/bin/env bash
# One machine verdict of a block run (R92): every sign-off gate re-read from the run's own files, nothing re-run.
#   qc18bacc/flow/signoff/verdict.sh [-g <gate,...>] <run dir> [top]      top: the block of <run dir>/out/<top>_pg.v
#   -g: the block's opt-in gates (common/block.sh BLK_GATES; signoff/verdict.py OPT_IN: the column's act_noise,
#   abstract_abutment), checked also whenever the run has their evidence
# Output: one "GATE <name> <corner|-> PASS|FAIL|MISSING <evidence>" line per gate, a VERDICT line naming the gates that
# did not pass, and the last line "SIGNOFF <top> PASS|FAIL"; exit status 0 only on PASS.  Gates (signoff/verdict.py): per
# sign-off corner (common/env.sh qb_corners) the PrimeTime log evidence (qb_pt -check), the sign-off limits in force
# (= common/limits.txt, R99), every QB_PT_SIGNOFF count (setup,
# hold, recovery, removal, max transition, max capacitance, clock max transition, min pulse width, min period, coverage;
# noise on the block's noise state with its driver-model counts; opt-in: the column's act load pins), the chip top's clock latency
# file (= the session's QB_PT_LAT line), the annotation split, the dont_use gate, the ETM (log, files, etmcheck) and the
# freshness chain netlist -> fill DEF -> SPEF -> PT -> ETM; for the block the ICC2 gate lines of summary.txt (dont_use,
# floorplan tracks, place / cts legality, route gate, last ECO round's gate, ECO names and loads of the round that built
# the label of out/, which must be complete [no unfinished label], abstract and its label [= the label of out/]; opt-in: the column's act / act_o abutment),
# Calibre LVS + its ERC (calibre/erc_allow.txt) / DRC (with the block deck's QB_ gate rules) / antenna (calibre/cal.sh check) and
# the chain GDS -> fill -> Calibre reports.  A gate whose evidence a run never produced is MISSING (it fails too).
# The step driver calls it last; the result table of the paper is made from its GATE lines.
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../common/env.sh"
g=(); if [ "${1:-}" = -g ]; then g=(-g "${2?-g <gate,...>}"); shift 2; fi
d=$(cd "${1:?run dir}" && pwd) || exit 1
top=${2:-$(basename "$(ls "$d"/out/*_pg.v 2> /dev/null | head -n 1)" _pg.v)}
[ -n "$top" ] || { echo "QB_FAIL verdict: no out/<top>_pg.v in $d"; echo "SIGNOFF ? FAIL"; exit 1; }
cs=$(qb_corners) || { echo "SIGNOFF $top FAIL"; exit 1; }
exec "$PY" -I "$here/verdict.py" "$d" "$top" "$QBF" ${g[@]+"${g[@]}"} $cs
