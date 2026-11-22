#!/usr/bin/env bash
# LVS source spice for a block / top (results/r38.md):  qc18bacc/flow/signoff/calibre/lvs_src.sh <pg.v> <out.spi> [extra .spi (macro stubs, block subckts)...]
#   (an extra x.spi with a sibling x.v is passed to v2lvs as a Verilog library -l x.v, else -lsp x.spi)
#   pgfix.py (drop FILL, add missing VDD / VSS) -> v2lvs with the std-cell spice for pin order; out.spi includes the cell spice.
set -u
here=$(cd "$(dirname "$0")" && pwd)
C=/CMC/tools/siemens/calibre/aok_cal_2026.1_26.19/aok_cal_2026.1_26.19
export CALIBRE_HOME=$C MGC_HOME=$C MGLS_LICENSE_FILE=${MGLS_LICENSE_FILE:-6056@engrcmc2.usask.ca}
SP=/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Back_End/spice/tcbn65gplus_200a/tcbn65gplus_200a.spi
PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3
vin=$1; out=$2; shift 2
d=$(dirname "$out"); b=$(basename "$out" .spi)
"$PY" -I "$here/pgfix.py" "$vin" "$SP" "$d/$b.fix.v" > "$d/$b.pgfix.txt" || { tail -5 "$d/$b.pgfix.txt"; echo "LVSSRC38 FAIL pgfix"; exit 1; }
head -30 "$d/$b.pgfix.txt"
lsp=""; inc="-s $SP"; for x in "$@"; do inc="$inc -s $x"; vx=${x%.spi}.v; if [ -f "$vx" ]; then lsp="$lsp -l $vx"; else lsp="$lsp -lsp $x"; fi; done
"$C/bin/v2lvs" -v "$d/$b.fix.v" -lsp "$SP" $lsp $inc -o "$out" -s0 VSS -s1 VDD > "$d/$b.v2lvs.log" 2>&1; rc=$?
echo "LVSSRC38 v2lvs rc $rc $(grep -ciE 'error' "$d/$b.v2lvs.log") error-lines; $(grep -ciE 'warning' "$d/$b.v2lvs.log") warning-lines"
grep -iE "error|warning" "$d/$b.v2lvs.log" | sort | uniq -c | sort -rn | head -8
rm -f "$d/$b.fix.v"; ls -la "$out"; exit $rc
