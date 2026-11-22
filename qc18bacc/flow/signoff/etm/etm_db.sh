#!/usr/bin/env bash
# PrimeTime copy of a block ETM with the outlier corrections the OpenROAD copy gets (results/r36.md, r43.md):
# <etm dir>/<blk>_<c>.lib -> etm_fix.py (rise / fall first-value outliers) -> etm_tables.py (second stage: outlier tables
# replaced by the nearest clean bus bit; for c != ss also tt hold tables above the ss ones + 0.5 ns) -> Library Compiler
# (flow/tsmc65/sram/lib2db.tcl) -> <out>/<blk>_<c>_lib.db
#   qc18bacc/flow/signoff/etm/etm_db.sh <blk> <etm dir> <out dir> [corners "tt ss ff"]
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$ROOT/flow/tsmc65/site/sram.sh"
b=$1; e=$2; o=$3; mkdir -p "$o/lc"
for c in ${4:-tt ss ff}; do
  mkdir -p "$o/lc/${b}_$c"; "$PY" -I "$here/etm_fix.py" "$e/${b}_$c.lib" "$o/lc/${b}_$c/${b}_${c}_syn.lib" | grep -c ETM_FIX
  f=$o/lc/${b}_$c/${b}_${c}_syn.lib; mv "$f" "$f.fix1"
  r=""; [ "$c" != ss ] && [ -f "$e/${b}_ss.lib" ] && r="2.0 $e/${b}_ss.lib 0.5"
  "$PY" -I "$here/etm_tables.py" "$f.fix1" "$f" $r | tee "$o/lc/${b}_$c/etm43.log" | tail -1
done
( cd "$o/lc" && tcsh -f -c "source $QC_MC_LC_SETUP >& /dev/null; lc_shell -f $ROOT/flow/tsmc65/sram/lib2db.tcl" > lib2db.log 2>&1 < /dev/null )
grep "DB_OK\|DB_FAIL" "$o/lc/lib2db.log"
for c in ${4:-tt ss ff}; do [ -f "$o/lc/${b}_$c/${b}_${c}_syn.db" ] && ln -sf "$o/lc/${b}_$c/${b}_${c}_syn.db" "$o/${b}_${c}_lib.db"; done
ls -la "$o"
