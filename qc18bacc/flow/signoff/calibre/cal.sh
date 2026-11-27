#!/usr/bin/env bash
# Calibre sign-off runs with the kit decks (results/r36.md, r38.md; decks copied per run with LAYOUT / SOURCE substituted):
#   qc18bacc/flow/signoff/calibre/cal.sh drc <gds> <topcell> <rundir> [turbo=8]   CLN65S_9M_6X2Z.23a (MAIN_DRC_TopMz), hierarchical
#   qc18bacc/flow/signoff/calibre/cal.sh ant <gds> <topcell> <rundir> [turbo=8]   CN65S_9M.ANT.23a
#   qc18bacc/flow/signoff/calibre/cal.sh lvs <gds> <topcell> <src.spi> <rundir> [turbo=8]  CRN65GP calibre.lvs (src.spi must include the cell spice)
#   qc18bacc/flow/signoff/calibre/cal.sh fill <gds> <topcell> <rundir> [turbo=8]  kit dummy metal (Dummy_Metal_Calibre_65nm.22c,
#        cell <topcell>_DM) placed at 0 0 in <topcell> -> <rundir>/<topcell>_fill.gds (calibredrv filemerge)
#   qc18bacc/flow/signoff/calibre/cal.sh odpo <gds> <topcell> <rundir> [turbo=8]  kit dummy OD / PO (CLN65GP autofill_OD_PO =
#        TN65CLDR001C2_V2.2B/Dummy_OD_PO_Calibre_65nm.22b, cell <topcell>_DODPO) merged the same way (R77)
#   qc18bacc/flow/signoff/calibre/cal.sh check <drc|ant|lvs|erc> <topcell> <rundir>   the result of a finished run from its
#        files alone (cal_result; no Calibre): what the run modes end with and signoff/verdict.py reads (R92; erc: the
#        ERC of an lvs run dir)
# env: QB36_DRC_SED / QB36_LVS_SED / QB55_FILL_SED / QB77_ODPO_SED = extra sed arguments for the deck copy (e.g. "-f drc_blk.sed"), QB36_LVS_EXTRA,
#      QB36_HCELL (hcell file)
# Summary: grep of the TOTAL counts and the rule checks with results (CAL36 lines), then cal_result's CAL36_RESULT line.
# Exit status (R92; before, Calibre's alone: r91b LVS INCORRECT + 4 DRC results ended "ok"): Calibre's if non-zero, else
# drc / ant / lvs: 1 unless cal_result passes (lvs: cal_result lvs and erc); fill / odpo: 1 if the merge failed.
set -u
C=/CMC/tools/siemens/calibre/aok_cal_2026.1_26.19/aok_cal_2026.1_26.19
export CALIBRE_HOME=$C MGC_HOME=$C MGLS_LICENSE_FILE=${MGLS_LICENSE_FILE:-6056@engrcmc2.usask.ca}
K=/CMC/kits/tsmc_65nm
A=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/erc_allow.txt   # (resolved before the run modes cd into their dirs)
# cal_result <drc|ant|lvs|erc> <topcell> <rundir>: one CAL36_RESULT line (+ CAL36_FAIL lines), non-zero unless
#   lvs       lvs.rep is this run's (not older than deck.lvs), its overall result is CORRECT, the CELL SUMMARY row of
#             <topcell> is CORRECT and no cell is INCORRECT / NOT COMPARED
#   drc, ant  the summary report the deck copy names is this run's and of <topcell>, has its TOTAL line with 0 results,
#             and every QB_* rule check of the deck copy (a gate a deck sed adds, R82 drc_blk.sed) has one RULECHECK
#             line, executed with 0 results (R84: a gate that did not run fails; R97: NOT EXECUTED fails too)
#   erc       the ERC summary of the lvs run (the deck copy's ERC SUMMARY REPORT; lvs ends with both) is this run's and
#             of <topcell>, at least one check executed, every executed check 0 results, its SUMMARY counts agree, and
#             a NOT EXECUTED check passes only if erc_allow.txt names it (reason from the deck) and every marker layer
#             it lists there has no original geometry in this layout (the summary's ORIGINAL LAYER STATISTICS: the
#             device does not exist); anything else fails
# Reads files only, so a missing, stale or truncated report fails instead of passing by default.
cal_result() {
    local mode=$1 top=$2 d=$3 rep f=0 o n b c r v q s="no report of this run"
    case $mode in
    lvs) rep=$d/lvs.rep
         if [ ! -s "$d/deck.lvs" ] || [ ! -s "$rep" ]; then echo "CAL36_FAIL lvs $top: no deck copy $d/deck.lvs or no report $rep"; f=1
         elif [ "$rep" -ot "$d/deck.lvs" ]; then echo "CAL36_FAIL lvs $top: $rep is older than deck.lvs (not this run's)"; f=1
         else
             o=$(sed -n '/OVERALL COMPARISON RESULTS/,/CELL  SUMMARY\|LVS PARAMETERS/s/.*# *\(NOT COMPARED\|INCORRECT\|CORRECT\) *#.*/\1/p' "$rep" | sort -u | tr '\n' ' ')
             n=$(awk -v t="$top" '/CELL  SUMMARY/ {f = 1; next} /LVS PARAMETERS/ {f = 0} f && $1 == "CORRECT" && $2 == t && $3 == t {c++} END {print c + 0}' "$rep")
             b=$(awk '/CELL  SUMMARY/ {f = 1; next} /LVS PARAMETERS/ {f = 0} f && /INCORRECT|NOT COMPARED/ {c++} END {print c + 0}' "$rep")
             s="overall ${o:-none }top_cell_correct $n bad_cells $b"
             [ "$o" = "CORRECT " ] && [ "$n" = 1 ] && [ "$b" = 0 ] || { echo "CAL36_FAIL lvs $top: $s"; f=1; }
         fi ;;
    drc|ant) rep=$d/$(sed -n 's/^DRC SUMMARY REPORT "\(.*\)".*/\1/p' "$d/deck.$mode" 2> /dev/null | head -1)
         if [ ! -s "$d/deck.$mode" ] || [ ! -f "$rep" ] || [ ! -s "$rep" ]; then echo "CAL36_FAIL $mode $top: no deck copy $d/deck.$mode or no summary report of it"; f=1
         elif [ "$rep" -ot "$d/deck.$mode" ]; then echo "CAL36_FAIL $mode $top: $rep is older than deck.$mode (not this run's)"; f=1
         else
             c=$(sed -n 's/^Layout Primary Cell: *//p' "$rep" | head -1)
             n=$(sed -n 's/^TOTAL DRC Results Generated: *\([0-9][0-9]*\) .*/\1/p' "$rep" | tail -1)
             r=$(grep -c '^RULECHECK ' "$rep"); v=$(grep -c '^RULECHECK .* TOTAL Result Count = [1-9]' "$rep")
             q=$(sed -n 's/^\(QB_[A-Za-z0-9_.]*\) *{.*/\1/p' "$d/deck.$mode")
             s="results ${n:-NA} rules_with_results $v rule_checks $r qb_gate_rules $(echo $q | wc -w)"
             [ "$c" = "$top" ] || { echo "CAL36_FAIL $mode $top: $rep is of cell '$c'"; f=1; }
             [ "$n" = 0 ] && [ "$v" = 0 ] && [ "$r" -gt 0 ] || { echo "CAL36_FAIL $mode $top: $s (needs the TOTAL line with 0 results and at least one rule check)"; f=1; }
             # our own deck gates (QB_* rule checks added by a deck sed, e.g. drc_blk.sed QB_BLK.M8M9.0): each passes only
             # with its RULECHECK line executed at 0 results (R97: "RULECHECK <rule> .... NOT EXECUTED" passed before)
             for b in $q; do
                 o=$(awk -v b="$b" '$1 == "RULECHECK" && $2 == b { n++; l = $0 }
                     END { if (n != 1) print n + 0 " RULECHECK lines"
                           else if (l !~ /^RULECHECK [^ ]+ \.+ TOTAL Result Count = 0 \(0\) *$/) { sub(/^RULECHECK [^ ]+ \.* */, "", l); print l } }' "$rep")
                 [ -z "$o" ] || { echo "CAL36_FAIL QB_ gate rule $b: $o in $rep (needs one RULECHECK line, executed, 0 results)"; f=1; }
             done
         fi ;;
    erc) rep=$(sed -n 's/^ERC SUMMARY REPORT "\(.*\)".*/\1/p' "$d/deck.lvs" 2> /dev/null | head -1); case $rep in /*) ;; *) rep=$d/$rep ;; esac
         if [ ! -s "$d/deck.lvs" ] || [ ! -f "$rep" ] || [ ! -s "$rep" ]; then echo "CAL36_FAIL erc $top: no deck copy $d/deck.lvs or no ERC summary of it"; f=1
         elif [ "$rep" -ot "$d/deck.lvs" ]; then echo "CAL36_FAIL erc $top: $rep is older than deck.lvs (not this run's)"; f=1
         else
             c=$(sed -n 's/^Layout Primary Cell: *//p' "$rep" | head -1)
             [ "$c" = "$top" ] || { echo "CAL36_FAIL erc $top: $rep is of cell '$c'"; f=1; }
             [ -s "$A" ] || { echo "CAL36_FAIL erc $top: no allow-list $A"; f=1; }
             # every RULECHECK line: "TOTAL Result Count = 0 (0)", or "NOT EXECUTED" for a check of erc_allow.txt whose
             # marker layers have no original geometry in this layout; the SUMMARY's executed count must match the lines
             o=$(awk -v al="$A" '
                 BEGIN { while ((getline l < al) > 0) if (l !~ /^#/ && split(l, h, " -- ") == 2 && split(h[1], w, " ") > 1) { k = w[1]; lay[k] = h[1]; sub(/^[^ ]+ +/, "", lay[k]) } }
                 /^LAYER [^ ]+ \.* *TOTAL Original Geometry Count = / { g[$2] = ($(NF-1) == 0 && $NF == "(0)") }
                 /^RULECHECK / { if ($0 ~ /^RULECHECK [^ ]+ \.* *TOTAL Result Count = 0 +\(0\) *$/) ex++
                     else if ($0 ~ /^RULECHECK [^ ]+ \.* *TOTAL Result Count = /) { bad = bad " " $2 "=" $(NF-1); ex++ }
                     else if ($0 ~ /^RULECHECK [^ ]+ \.* *NOT EXECUTED *$/) { ne++; ns[ne] = $2 } else bad = bad " " $2 "=unparsed" }
                 /^TOTAL ERC RuleChecks Executed: / { tx = $NF }
                 /^TOTAL ERC RuleCheck Results Generated: / { tr = $(NF-1) " " $NF }
                 END { for (i = 1; i <= ne; i++) { k = ns[i]; e = (k in lay)
                           if (e) { n = split(lay[k], w, " "); for (j = 1; j <= n; j++) if (!g[w[j]]) e = 0 }
                           if (e) ok = ok " " k; else bad = bad " " k "=not_executed" }
                       if (tx != ex + 0) bad = bad " summary_executed=" tx
                       if (tr != "0 (0)") bad = bad " summary_results=" tr
                       printf "executed %d not_executed %d allowed %d (%s) bad %s\n", ex, ne, split(ok, w, " "), substr(ok, 2), bad == "" ? "none" : substr(bad, 2) }' "$rep")
             s="$o"
             case $o in "executed "[1-9]*" bad none") ;; *) echo "CAL36_FAIL erc $top: $s (needs every executed check at 0 results and every NOT EXECUTED one in $A with its marker layers empty)"; f=1 ;; esac
         fi ;;
    *) echo "CAL36_FAIL cal_result: mode $mode"; return 1 ;;
    esac
    echo "CAL36_RESULT $mode $top $([ $f = 0 ] && echo PASS || echo FAIL) $s"
    return $f
}
mode=${1:?drc|ant|lvs|fill|odpo|check}; gds=${2:?}; top=${3:?}; res=0
case $mode in
drc|ant) d=$4; t=${5:-8}; mkdir -p "$d"; cd "$d" || exit 1
     [ $mode = drc ] && deck=$K/CLN65GP/DRC/MAIN_DRC_TopMz/CLN65S_9M_6X2Z.23a || deck=$K/CLN65GP/DRC/ANTENNA_DRC/CN65S_9M.ANT.23a
     sed -e "s#^\(LAYOUT PATH\) .*#\1 \"$gds\"#" -e "s#^\(LAYOUT PRIMARY\) .*#\1 \"$top\"#" \
         -e "s#^DRC MAXIMUM RESULTS ALL#DRC MAXIMUM RESULTS 1000#" ${QB36_DRC_SED:-} "$deck" > deck.$mode
     /usr/bin/time -v "$C/bin/calibre" -drc -hier -turbo "$t" deck.$mode > cal_$mode.log 2> cal_$mode.time; rc=$?
     rep=$(sed -n 's/^DRC SUMMARY REPORT "\(.*\)".*/\1/p' deck.$mode | head -1)
     echo "CAL36 $mode $top rc $rc $(grep 'TOTAL DRC Results Generated' "$rep") wall $(grep Elapsed cal_$mode.time | awk '{print $NF}') rss_kb $(grep Maximum cal_$mode.time | awk '{print $NF}')"
     grep "RULECHECK .* TOTAL Result Count = [1-9]" "$rep" | awk '{print "CAL36_RULE", $2, $(NF-1)}' | head -60
     cal_result $mode "$top" . || res=1 ;;
fill|odpo) d=$4; t=${5:-8}; mkdir -p "$d"; cd "$d" || exit 1
     if [ $mode = fill ]; then deck=$K/CLN65GP/TN65CLDR001C3_V2.2C/Dummy_Metal_Calibre_65nm.22c; db=DM; sx=${QB55_FILL_SED:-}
     else deck=$K/CLN65GP/autofill_OD_PO/Dummy_OD_PO_Calibre_65nm.22b; db=DODPO; sx=${QB77_ODPO_SED:-}; fi
     sed -e "s#^\(LAYOUT PATH\) .*#\1 \"$gds\"#" -e "s#^\(LAYOUT PRIMARY\) .*#\1 \"$top\"#" \
         -e "s#^DRC RESULTS DATABASE \"$db.gds\" GDSII .*#DRC RESULTS DATABASE \"$db.gds\" GDSII _$db#" $sx "$deck" > deck.$mode
     /usr/bin/time -v "$C/bin/calibre" -drc -hier -turbo "$t" deck.$mode > cal_$mode.log 2> cal_$mode.time; rc=$?
     [ $rc = 0 ] && "$C/bin/calibredrv" -a layout filemerge -in "$gds" \
         -infile "{-name $db.gds -placecell {-refcell ${top}_$db -incell $top -x 0 -y 0}}" -out "${top}_fill.gds" > merge.log 2>&1 || rc=1
     sum=$(sed -n 's/^DRC SUMMARY REPORT "\(.*\)".*/\1/p' deck.$mode | head -1)
     echo "CAL55 $mode $top rc $rc $(grep 'TOTAL DRC Results Generated' "$sum") wall $(grep Elapsed cal_$mode.time | awk '{print $NF}') out $(ls -s "${top}_fill.gds" 2>/dev/null)"
     grep "RULECHECK .* TOTAL Result Count = [1-9]" "$sum" | awk -v m=$mode '{print "CAL55_" m, $2, $(NF-1)}' | head -40 ;;
lvs) src=$4; d=$5; t=${6:-8}; mkdir -p "$d"; cd "$d" || exit 1; L=$K/CRN65GP/TN65CMSP018K1_V1.0C/Calibre/lvs
     sed -e "s#^LAYOUT PRIMARY .*#LAYOUT PRIMARY \"$top\"#" -e "s#^LAYOUT PATH .*#LAYOUT PATH \"$gds\"#" \
         -e "s#^SOURCE PRIMARY .*#SOURCE PRIMARY \"$top\"#" -e "s#^SOURCE PATH .*#SOURCE PATH \"$src\"#" \
         -e "s#^INCLUDE ./DFM/dfm_device#INCLUDE $L/DFM/dfm_device#" ${QB36_LVS_SED:-} "$L/calibre.lvs" > deck.lvs
     [ -n "${QB36_LVS_EXTRA:-}" ] && cat "$QB36_LVS_EXTRA" >> deck.lvs
     hc=""; if [ -n "${QB36_HCELL:-}" ]; then hc="-hcell $QB36_HCELL"; fi
     /usr/bin/time -v "$C/bin/calibre" -lvs -hier $hc -turbo "$t" deck.lvs > cal_lvs.log 2> cal_lvs.time; rc=$?
     echo "CAL36 lvs $top rc $rc wall $(grep Elapsed cal_lvs.time | awk '{print $NF}') rss_kb $(grep Maximum cal_lvs.time | awk '{print $NF}')"
     grep -m4 "CORRECT\|INCORRECT\|NOT COMPARED" lvs.rep; awk '/CELL  SUMMARY/{f=1} f && /INCORRECT|NOT COMPARED/ {print "CAL36_CELL", $0} /LVS PARAMETERS/{f=0}' lvs.rep | head -40
     cal_result lvs "$top" . || res=1; cal_result erc "$top" . || res=1 ;;
check) cal_result "$2" "$3" "${4:?rundir}"; exit ;;
*) sed -n '2,11p' "$0"; exit 1 ;;
esac
[ $rc = 0 ] || exit $rc     # Calibre's own failure first
exit $res
