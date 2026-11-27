#!/usr/bin/env bash
# LVS source spice for a block / top (results/r38.md):  qc18bacc/flow/signoff/calibre/lvs_src.sh <pg.v> <out.spi> [extra .spi (macro stubs, block subckts)...]
#   (an extra x.spi with a sibling x.v is passed to v2lvs as a Verilog library -l x.v, else -lsp x.spi)
#   pgfix.py (drop FILL, add missing VDD / VSS) -> v2lvs with the std-cell spice for pin order; out.spi includes the cell spice.
#   Record (R106): <out dir>/<out>.inputs.txt, one line "input <file> md5 <md5>" per netlist read (pg.v, then the extras),
#   written once out.spi is built (signoff/verdict.py lvs_source_netlist compares it with out/<top>_pg.v).
#   Exit status non-zero on v2lvs's, or on any error / warning line of its log v2lvs_allow.txt does not allow (R109).
set -u
here=$(cd "$(dirname "$0")" && pwd)
C=/CMC/tools/siemens/calibre/aok_cal_2026.1_26.19/aok_cal_2026.1_26.19
export CALIBRE_HOME=$C MGC_HOME=$C MGLS_LICENSE_FILE=${MGLS_LICENSE_FILE:-6056@engrcmc2.usask.ca}
SP=/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Back_End/spice/tcbn65gplus_200a/tcbn65gplus_200a.spi
PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3
vin=$1; out=$2; shift 2
d=$(dirname "$out"); b=$(basename "$out" .spi); rec=$d/$b.inputs.txt
rm -f "$rec"; ins=$(for x in "$vin" "$@"; do echo "input $x md5 $(md5sum < "$x" | cut -c1-32)"; done)
"$PY" -I "$here/pgfix.py" "$vin" "$SP" "$d/$b.fix.v" > "$d/$b.pgfix.txt" || { tail -5 "$d/$b.pgfix.txt"; echo "LVSSRC38 FAIL pgfix"; exit 1; }
head -30 "$d/$b.pgfix.txt"
lsp=""; inc="-s $SP"; for x in "$@"; do inc="$inc -s $x"; vx=${x%.spi}.v; if [ -f "$vx" ]; then lsp="$lsp -l $vx"; else lsp="$lsp -lsp $x"; fi; done
"$C/bin/v2lvs" -v "$d/$b.fix.v" -lsp "$SP" $lsp $inc -o "$out" -s0 VSS -s1 VDD > "$d/$b.v2lvs.log" 2>&1; rc=$?
ne=$(grep -ciE 'error' "$d/$b.v2lvs.log")
echo "LVSSRC38 v2lvs rc $rc $ne error-lines; $(grep -ciE 'warning' "$d/$b.v2lvs.log") warning-lines"
grep -iE "error|warning" "$d/$b.v2lvs.log" | sort | uniq -c | sort -rn | head -8
rm -f "$d/$b.fix.v"; ls -la "$out"
[ $rc = 0 ] || exit $rc
# (R109; hunt round 12: the error / warning lines were counted, only the exit status gated) every line of the v2lvs log
# with "error" or "warning" fails unless an ERE of v2lvs_allow.txt (benign warnings, each with its reason) matches it.
# [M] tau14 seeds on the rgf51c41ba netlist: an instance of an undeclared module and a pin the cell lacks are warnings at
# exit status 0 ("No module declaration for module ..."; v2lvs leaves a black box), a doubled pin an error at status 1
na=$(grep -iE 'error|warning' "$d/$b.v2lvs.log" | grep -vEf <(sed -n 's/^\(.*\) -- .*/\1/p' "$here/v2lvs_allow.txt") | grep -c .)
[ -s "$here/v2lvs_allow.txt" ] && [ "$na" = 0 ] \
    || { echo "LVSSRC38 FAIL v2lvs: $na error / warning line(s) not in $here/v2lvs_allow.txt:"; grep -iE 'error|warning' "$d/$b.v2lvs.log" | grep -vEf <(sed -n 's/^\(.*\) -- .*/\1/p' "$here/v2lvs_allow.txt") | head -5; exit 1; }
echo "$ins" > "$rec" && cat "$rec"
