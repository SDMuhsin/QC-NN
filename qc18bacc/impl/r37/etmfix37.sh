#!/usr/bin/env bash
# R37 (results/r37.md): ETM acceptance for a block view dir.  For each corner: impl/r35/etmcheck.py on <dir>/<top>_<c>.lib;
# if values are beyond +-LIM, impl/r7b/etm_fix.py (R6c: one-edge extraction outliers -> the other edge's table) writes
# <top>_<c>_fix.lib, Library Compiler compiles it to <top>_<c>_fix_lib.db, and etmcheck runs again on the fixed .lib.
#   qc18bacc/impl/r37/etmfix37.sh <dir> <top> [LIM 3.0] [corners "tt ss ff"]
set -u
here=$(cd "$(dirname "$0")" && pwd); I=$(cd "$here/.." && pwd); root=$(cd "$I/../.." && pwd)
d=${1:?dir}; top=${2:?top}; LIM=${3:-3.0}; PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3
LC=${QB37_LC:-/CMC/tools/synopsys/lc_vP-2019.03/bin/lc_shell}
for c in ${4:-tt ss ff}; do
  l=$d/${top}_$c.lib; "$PY" -I "$I/r35/etmcheck.py" "$l" "$LIM" | tee "$d/etmcheck_$c.txt"
  if awk -v n=0 '/beyond/ { n += $NF } END { exit !(n > 0) }' "$d/etmcheck_$c.txt"; then
    "$PY" -I "$I/r7b/etm_fix.py" "$l" "$d/${top}_${c}_fix.lib" 2.0 | grep ETM_FIX | tee "$d/etmfix_$c.txt" | head -20
    lib=$(grep -m1 "^library" "$d/${top}_${c}_fix.lib" | sed 's/library *( *"\?\([^")]*\)"\?.*/\1/')
    ( . "$root/flow/tsmc65/common/tool.sh" >/dev/null 2>&1; cd "$d" && tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; $LC -no_gui" > "lc_$c.log" 2>&1 <<LCEOF
read_lib ${top}_${c}_fix.lib
write_lib $lib -format db -output ${top}_${c}_fix_lib.db
quit
LCEOF
    ); ls -la "$d/${top}_${c}_fix_lib.db" || echo "R37_ETMFIX lc failed $c (see $d/lc_$c.log)"
    "$PY" -I "$I/r35/etmcheck.py" "$d/${top}_${c}_fix.lib" "$LIM" | tee "$d/etmcheck_${c}_fix.txt"
  fi
done
