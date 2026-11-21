#!/usr/bin/env bash
# R36: PrimeTime copy of a block ETM with the impl/r7b/etm_fix.py outlier correction (the same correction the OR copy
# gets): <etm dir>/<blk>_<c>.lib -> etm_fix -> Library Compiler (flow/tsmc65/sram/lib2db.tcl) -> <out>/<blk>_<c>_lib.db
#   etmdb.sh <blk> <etm dir> <out dir> [corners "tt ss ff"]
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd); . "$root/flow/tsmc65/site/sram.sh"
PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3
b=$1; e=$2; o=$3; mkdir -p "$o/lc"
for c in ${4:-tt ss ff}; do
  mkdir -p "$o/lc/${b}_$c"; "$PY" -I "$root/qc18bacc/impl/r7b/etm_fix.py" "$e/${b}_$c.lib" "$o/lc/${b}_$c/${b}_${c}_syn.lib" | grep -c ETM_FIX
  # R43 opt-in QB43_ETM43 1: second-stage outlier-table correction (impl/r43/etm43.py, results/r43.md)
  if [ "${QB43_ETM43:-0}" = 1 ]; then f=$o/lc/${b}_$c/${b}_${c}_syn.lib; mv "$f" "$f.fix1"
    r=""; [ "$c" != ss ] && [ -f "$e/${b}_ss.lib" ] && r="2.0 $e/${b}_ss.lib 0.5"
    "$PY" -I "$root/qc18bacc/impl/r43/etm43.py" "$f.fix1" "$f" $r | tee "$o/lc/${b}_$c/etm43.log" | tail -1; fi
done
( cd "$o/lc" && tcsh -f -c "source $QC_MC_LC_SETUP >& /dev/null; lc_shell -f $root/flow/tsmc65/sram/lib2db.tcl" > lib2db.log 2>&1 < /dev/null )
grep "DB_OK\|DB_FAIL" "$o/lc/lib2db.log"
for c in ${4:-tt ss ff}; do [ -f "$o/lc/${b}_$c/${b}_${c}_syn.db" ] && ln -sf "$o/lc/${b}_$c/${b}_${c}_syn.db" "$o/${b}_${c}_lib.db"; done
ls -la "$o"
