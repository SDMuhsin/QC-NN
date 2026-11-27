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
#   qc18bacc/flow/signoff/calibre/cal.sh check deck <topcell> <rundir>   the deck edits of any run mode's dir took effect
#        in its deck copy (cal_deck, R109)
# env: QB36_DRC_SED / QB36_ANT_SED / QB36_LVS_SED / QB55_FILL_SED / QB77_ODPO_SED = extra sed arguments for the deck copy
#      of that mode only (e.g. "-f drc_blk.sed"; common/block.sh sets each one explicitly per run), QB36_LVS_EXTRA,
#      QB36_HCELL (hcell file); QB55_WINDOW = a sed file of the chip window (fill / odpo: common/block.sh die_window.sed)
# Record (R106): every run mode writes <rundir>/deck_edits.txt, one line "deck_edits <mode> <var>=<value> ..." of the
# edits / add-ons it applied to the deck copy (the env variables of that mode above; common/env.sh qb_knob words, an
# empty value as <unset>), which signoff/verdict.py compares with the block's committed defaults (before, they were only
# in the step's BLK_KNOBS line, which only common/regress.sh read: an experiment's deck edit could sign off).
# Summary: grep of the TOTAL counts and the rule checks with results (CAL36 lines), then cal_result's CAL36_RESULT line.
# Exit status (R92; before, Calibre's alone: r91b LVS INCORRECT + 4 DRC results ended "ok"): Calibre's if non-zero, else
# drc / ant / lvs: 1 unless cal_result passes (lvs: cal_result lvs and erc); fill / odpo: 1 if the merge failed or the
# results GDS / merged GDS is missing or older than its input (R104).
set -u
C=/CMC/tools/siemens/calibre/aok_cal_2026.1_26.19/aok_cal_2026.1_26.19
export CALIBRE_HOME=$C MGC_HOME=$C MGLS_LICENSE_FILE=${MGLS_LICENSE_FILE:-6056@engrcmc2.usask.ca}
K=/CMC/kits/tsmc_65nm
A=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/erc_allow.txt   # (resolved before the run modes cd into their dirs)
AD=${A%/*}/drc_allow.txt
. "${A%/*}/../../common/env.sh"   # (qb_knob: the deck edit record)
cal_edits() {   # cal_edits <mode> <var> ...: deck_edits.txt of the current (run) dir
    local m=$1 v; shift
    { printf 'deck_edits %s' "$m"; for v; do if [ -n "${!v:-}" ]; then printf ' %s' "$(qb_knob "$v")"; else printf ' %s=<unset>' "$v"; fi; done; echo; } > deck_edits.txt
}
# The deck edits took effect (R109; hunt round 12: a sed expression that matches nothing is a silent no-op, and nothing
# looked into the deck copy).  Every deck sed file (signoff/calibre/*_blk.sed, lvs_case.sed, the run's die_window.sed)
# states the results of its edits as comment lines "#@expect <ERE>" (a line of the deck copy must match) and "#@absent
# <ERE>" (no line may match); a sed file without one fails (its edits are unverifiable).
# cal_deck <rundir>: one CAL_DECK line; non-zero unless deck_edits.txt is there and every sed file it records (the -f
# files of the *_SED values, QB55_WINDOW) is readable and every one of its #@expect / #@absent lines holds in
# deck.<mode> of <rundir>.  Run by every run mode right after the deck copy (before Calibre) and by check deck
# (signoff/verdict.py deck_<mode>).
cal_deck() {
    local d=$1 m w k v a=() i f n=0 bad=()
    read -ra w < "$d/deck_edits.txt" 2> /dev/null; m=${w[1]:-}
    [ "${w[0]:-}" = deck_edits ] && [ -s "$d/deck.$m" ] || { echo "CAL_DECK FAIL $d: no deck_edits.txt or no deck copy deck.${m:-?}"; return 1; }
    for k in "${w[@]:2}"; do
        v=${k#*=}; [ "$v" != "<unset>" ] || continue; v=${v//<flow>/$QBF}; v=${v//,/ }
        case ${k%%=*} in QB55_WINDOW) a+=(-f "$v") ;; *_SED) a+=($v) ;; esac
    done
    for ((i = 0; i < ${#a[@]}; i++)); do
        [ "${a[i]}" = -f ] || continue; f=${a[i + 1]:-}
        [ -r "$f" ] || { bad+=("unreadable:$f"); continue; }
        grep -q '^#@\(expect\|absent\) ' "$f" || { bad+=("no_#@expect:${f##*/}"); continue; }
        while IFS= read -r v; do n=$((n + 1)); k=${v%% *}; v=${v#* }
            if [ "$k" = "#@expect" ]; then grep -Eq -- "$v" "$d/deck.$m" || bad+=("missing:${f##*/}:'$v'")
            else ! grep -Eq -- "$v" "$d/deck.$m" || bad+=("present:${f##*/}:'$v'"); fi
        done < <(grep '^#@\(expect\|absent\) ' "$f")
    done
    echo "CAL_DECK $([ ${#bad[@]} = 0 ] && echo PASS || echo FAIL) $m: $n expected edit results of the sed files (${a[*]//$QBF/<flow>}) in deck.$m; bad ${#bad[@]} ${bad[*]:0:6}"
    [ ${#bad[@]} = 0 ]
}
# cal_result <drc|ant|lvs|erc> <topcell> <rundir>: one CAL36_RESULT line (+ CAL36_FAIL lines), non-zero unless
#   lvs       lvs.rep is this run's (not older than deck.lvs), its overall result is CORRECT, the CELL SUMMARY row of
#             <topcell> is CORRECT and no cell is INCORRECT / NOT COMPARED, and the extraction report lvs.rep.ext of
#             this run has no line after its header (no extraction / soft-connection finding, R99), and the ports pass
#             lvs_ports (R103)
#   drc, ant  the summary report the deck copy names is this run's and of <topcell>, has its TOTAL line with 0 results,
#             and every QB_* rule check of the deck copy (a gate a deck sed adds, R82 drc_blk.sed) has one RULECHECK
#             line, executed with 0 results (R84: a gate that did not run fails; R97: NOT EXECUTED fails too); the set of
#             NOT EXECUTED rule checks is exactly the mode's rules of drc_allow.txt (R106; before, only QB_* rules had to
#             execute, so a deck edit that dropped a kit rule's input passed)
#   erc       the ERC summary of the lvs run (the deck copy's ERC SUMMARY REPORT; lvs ends with both) is this run's and
#             of <topcell>, at least one check executed, every executed check 0 results, its SUMMARY counts agree, and
#             a NOT EXECUTED check passes only if erc_allow.txt names it (reason from the deck) and every marker layer
#             it lists there has no original geometry in this layout (the summary's ORIGINAL LAYER STATISTICS: the
#             device does not exist); anything else fails
# Reads files only, so a missing, stale or truncated report fails instead of passing by default.
# lvs_ports <rundir> <topcell> <lvs.rep>: the LVS port gate (R103); prints "ports ..." and is non-zero unless the
# layout's top-cell ports (svdb/<top>.sp .SUBCKT, which must be this run's: not older than deck.lvs, R104) are by name
# the source's (the deck's SOURCE PATH .SUBCKT), the
# report's initial layout port count is their number and both counts after transformation are it too, no layout
# passthrough net was deleted, and the source's surplus of initial ports = its passthrough nets deleted = its global
# nets that are not top-cell ports (.GLOBAL of the source and its .INCLUDE files; LVS GLOBALS ARE PORTS YES makes each
# a port).  CORRECT allows a port count mismatch Calibre resolves itself; [M] rgr rg8b1bc0ea (CORRECT): ports 122 / 123,
# nets 13585 / 13586, "1 passthrough source net was deleted", 122 / 122 after transformation = VDDL of the cell spice's
# ".GLOBAL VDD VSS VDDL", which only the 16 LVLLH* level shifters use and the design has none of.  The other warnings
# of that run were classified as artefacts: "Unbalanced smashed mosfets" / MN 16462 vs 16040, MP 16637 vs 16213 =
# fingers the layout extraction and the cell spice split differently, equal after parallel reduction (2457 / 2457 each,
# every instance matched); "849 nets and 291 instances were matched arbitrarily" = 849 internal net8 nets of DCAP64
# fillers and 291 device groups each inside one cell instance (swappable parallel devices).
lvs_subckt_ports() {   # lvs_subckt_ports <cell> <spice>: the port names of .SUBCKT <cell>, sorted
    awk -v t="$1" 'toupper($1) == ".SUBCKT" && $2 == t { f = 1; for (i = 3; i <= NF; i++) print $i; next }
                   f && /^\+/ { for (i = 2; i <= NF; i++) print $i; next } f { exit }' "$2" 2> /dev/null | LC_ALL=C sort
}
lvs_ports() {
    local d=$1 top=$2 rep=$3 src sl ss il is tl ts ps pl g ng sp=$1/svdb/$2.sp fr=fresh
    src=$(sed -n 's/^SOURCE PATH *"\(.*\)".*/\1/p' "$d/deck.lvs" | head -1)
    # (R104; hunt round 9 on 018af5e: a svdb/<top>.sp left by an earlier run was read as this run's layout ports)
    [ -s "$sp" ] && ! [ "$sp" -ot "$d/deck.lvs" ] || { fr=stale; sp=/dev/null; }
    sl=$(lvs_subckt_ports "$top" "$sp"); ss=$(lvs_subckt_ports "$top" "$src")
    read -r il is < <(awk '/^INITIAL NUMBERS OF OBJECTS/ { f = 1 } f && $1 == "Ports:" { print $2, $3; exit }' "$rep")
    read -r tl ts < <(awk '/^NUMBERS OF OBJECTS AFTER TRANSFORMATION/ { f = 1 } f && $1 == "Ports:" { print $2, $3; exit }' "$rep")
    ps=$(sed -n 's/^ *\([0-9][0-9]*\) passthrough source nets\{0,1\} w[a-z]* deleted\..*/\1/p' "$rep" | head -1)
    pl=$(sed -n 's/^ *\([0-9][0-9]*\) passthrough layout nets\{0,1\} w[a-z]* deleted\..*/\1/p' "$rep" | head -1)
    g=$({ cat "$src"; sed -n 's/^\.INCLUDE *"\{0,1\}\([^" ]*\)"\{0,1\}.*/\1/Ip' "$src" | xargs -r cat; } 2> /dev/null \
        | awk 'toupper($1) == ".GLOBAL" { for (i = 2; i <= NF; i++) print $i }' | LC_ALL=C sort -u | LC_ALL=C comm -23 - <(LC_ALL=C sort -u <<< "$ss"))
    ng=$(grep -c . <<< "$g")
    echo "ports layout_netlist $fr layout ${il:-NA} source ${is:-NA} after_transformation ${tl:-NA}/${ts:-NA} top_cell_port_names $([ -n "$sl" ] && [ "$sl" = "$ss" ] && echo equal || echo differ)($(grep -c . <<< "$sl")/$(grep -c . <<< "$ss")) passthrough_deleted source ${ps:-0} layout ${pl:-0} source_globals_not_ports $ng ($(echo $g))"
    [ -n "$sl" ] && [ "$sl" = "$ss" ] && [ "$il" = "$(grep -c . <<< "$sl")" ] && [ "$tl" = "$il" ] && [ "$ts" = "$il" ] \
        && [ "${pl:-0}" = 0 ] && [ -n "$is" ] && [ $((is - il)) = "${ps:-0}" ] && [ "${ps:-0}" = "$ng" ]
}
# cal_named <deck copy> <statement>: the file a deck statement names ('<statement> "<file>"', its first one): as written
# if absolute, else in the deck copy's dir (R109; hunt round 12: drc / ant always prefixed the dir, so an absolute summary
# path failed; erc had this rule alone); nothing printed without the statement
cal_named() {
    local r; r=$(sed -n "s/^$2 \"\(.*\)\".*/\1/p" "$1" 2> /dev/null | head -1)
    case $r in '') ;; /*) echo "$r" ;; *) echo "${1%/*}/$r" ;; esac
}
cal_result() {
    local mode=$1 top=$2 d=$3 rep f=0 o n b c r v q x s="no report of this run"
    case $mode in
    lvs) rep=$d/lvs.rep
         if [ ! -s "$d/deck.lvs" ] || [ ! -s "$rep" ]; then echo "CAL36_FAIL lvs $top: no deck copy $d/deck.lvs or no report $rep"; f=1
         elif [ "$rep" -ot "$d/deck.lvs" ]; then echo "CAL36_FAIL lvs $top: $rep is older than deck.lvs (not this run's)"; f=1
         else
             o=$(sed -n '/OVERALL COMPARISON RESULTS/,/CELL  SUMMARY\|LVS PARAMETERS/s/.*# *\(NOT COMPARED\|INCORRECT\|CORRECT\) *#.*/\1/p' "$rep" | sort -u | tr '\n' ' ')
             n=$(awk -v t="$top" '/CELL  SUMMARY/ {f = 1; next} /LVS PARAMETERS/ {f = 0} f && $1 == "CORRECT" && $2 == t && $3 == t {c++} END {print c + 0}' "$rep")
             b=$(awk '/CELL  SUMMARY/ {f = 1; next} /LVS PARAMETERS/ {f = 0} f && /INCORRECT|NOT COMPARED/ {c++} END {print c + 0}' "$rep")
             # the circuit extraction report (R99): its header only.  [M] a VDD-tied N-well tap bridged to a signal net
             # (an SCONNECT "Stamping conflict" warning, there and nowhere else) left lvs.rep CORRECT and the ERC clean
             x=$(awk '/^CALIBRE VERSION:/ { h = 1; next } h && NF { n++ } END { print h ? n + 0 : "no_header" }' "$d/lvs.rep.ext" 2> /dev/null)
             [ -s "$d/lvs.rep.ext" ] && ! [ "$d/lvs.rep.ext" -ot "$d/deck.lvs" ] || x=missing
             q=$(lvs_ports "$d" "$top" "$rep"); r=$?
             s="overall ${o:-none }top_cell_correct $n bad_cells $b extraction_report_lines ${x:-NA} $q"
             [ "$o" = "CORRECT " ] && [ "$n" = 1 ] && [ "$b" = 0 ] && [ "$x" = 0 ] && [ $r = 0 ] || { echo "CAL36_FAIL lvs $top: $s"; f=1; }
             [ "$x" = 0 ] || grep -m 6 '^WARNING:\|^ERROR:\|^ *Net \|^ *Rejected\|Errors and Warnings' "$d/lvs.rep.ext" 2> /dev/null | sed 's/^/CAL36_FAIL lvs.rep.ext: /'
         fi ;;
    drc|ant) rep=$(cal_named "$d/deck.$mode" 'DRC SUMMARY REPORT')
         if [ ! -s "$d/deck.$mode" ] || [ ! -f "$rep" ] || [ ! -s "$rep" ]; then echo "CAL36_FAIL $mode $top: no deck copy $d/deck.$mode or no summary report of it"; f=1
         elif [ "$rep" -ot "$d/deck.$mode" ]; then echo "CAL36_FAIL $mode $top: $rep is older than deck.$mode (not this run's)"; f=1
         else
             c=$(sed -n 's/^Layout Primary Cell: *//p' "$rep" | head -1)
             n=$(sed -n 's/^TOTAL DRC Results Generated: *\([0-9][0-9]*\) .*/\1/p' "$rep" | tail -1)
             r=$(grep -c '^RULECHECK ' "$rep"); v=$(grep -c '^RULECHECK .* TOTAL Result Count = [1-9]' "$rep")
             q=$(sed -n 's/^\(QB_[A-Za-z0-9_.]*\) *{.*/\1/p' "$d/deck.$mode")
             # NOT EXECUTED rule checks = the allow-list's of this mode, no more, no fewer (R106)
             x=$(awk '$1 == "RULECHECK" && / NOT EXECUTED *$/ { print $2 }' "$rep" | LC_ALL=C sort -u)
             o=$(awk -v m=$mode '!/^#/ && $1 == m && $3 == "--" { print $2 }' "$AD" 2> /dev/null | LC_ALL=C sort -u)
             s="results ${n:-NA} rules_with_results $v rule_checks $r qb_gate_rules $(echo $q | wc -w) not_executed $(grep -c . <<< "$x") ($(echo $x))"
             [ -s "$AD" ] && [ "$x" = "$o" ] || { echo "CAL36_FAIL $mode $top: NOT EXECUTED rule checks ($(echo $x)) are not the allowed ones of $AD ($(echo $o))"; f=1; }
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
    erc) rep=$(cal_named "$d/deck.lvs" 'ERC SUMMARY REPORT')
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
     # each mode its own deck edits (R104; hunt round 9 on 018af5e: ant read QB36_DRC_SED too, so the DRC deck's
     # edits, or any value inherited from the environment, reached the antenna deck)
     if [ $mode = drc ]; then deck=$K/CLN65GP/DRC/MAIN_DRC_TopMz/CLN65S_9M_6X2Z.23a; sx=${QB36_DRC_SED:-}
     else deck=$K/CLN65GP/DRC/ANTENNA_DRC/CN65S_9M.ANT.23a; sx=${QB36_ANT_SED:-}; fi
     sed -e "s#^\(LAYOUT PATH\) .*#\1 \"$gds\"#" -e "s#^\(LAYOUT PRIMARY\) .*#\1 \"$top\"#" \
         -e "s#^DRC MAXIMUM RESULTS ALL#DRC MAXIMUM RESULTS 1000#" $sx "$deck" > deck.$mode
     cal_edits $mode $([ $mode = drc ] && echo QB36_DRC_SED || echo QB36_ANT_SED)
     cal_deck . || exit 1
     /usr/bin/time -v "$C/bin/calibre" -drc -hier -turbo "$t" deck.$mode > cal_$mode.log 2> cal_$mode.time; rc=$?
     rep=$(sed -n 's/^DRC SUMMARY REPORT "\(.*\)".*/\1/p' deck.$mode | head -1)
     echo "CAL36 $mode $top rc $rc $(grep 'TOTAL DRC Results Generated' "$rep") wall $(grep Elapsed cal_$mode.time | awk '{print $NF}') rss_kb $(grep Maximum cal_$mode.time | awk '{print $NF}')"
     grep "RULECHECK .* TOTAL Result Count = [1-9]" "$rep" | awk '{print "CAL36_RULE", $2, $(NF-1)}' | head -60
     cal_result $mode "$top" . || res=1 ;;
fill|odpo) d=$4; t=${5:-8}; mkdir -p "$d"; cd "$d" || exit 1
     if [ $mode = fill ]; then deck=$K/CLN65GP/TN65CLDR001C3_V2.2C/Dummy_Metal_Calibre_65nm.22c; db=DM; e=QB55_FILL_SED
     else deck=$K/CLN65GP/autofill_OD_PO/Dummy_OD_PO_Calibre_65nm.22b; db=DODPO; e=QB77_ODPO_SED; fi
     sx="${!e:-} ${QB55_WINDOW:+-f $QB55_WINDOW}"
     sed -e "s#^\(LAYOUT PATH\) .*#\1 \"$gds\"#" -e "s#^\(LAYOUT PRIMARY\) .*#\1 \"$top\"#" \
         -e "s#^DRC RESULTS DATABASE \"$db.gds\" GDSII .*#DRC RESULTS DATABASE \"$db.gds\" GDSII _$db#" $sx "$deck" > deck.$mode
     cal_edits $mode $e QB55_WINDOW
     cal_deck . || exit 1
     sum=$(sed -n 's/^DRC SUMMARY REPORT "\(.*\)".*/\1/p' deck.$mode | head -1)
     # the outputs of this run only (R104; hunt round 9 on 018af5e: a DM.gds of an earlier run stayed when Calibre
     # wrote none, and fill_def.py / the merge read it): removed first, then each must be there and newer than its input
     rm -f "$db.gds" "${top}_fill.gds" merge.log ${sum:+"$sum"}
     /usr/bin/time -v "$C/bin/calibre" -drc -hier -turbo "$t" deck.$mode > cal_$mode.log 2> cal_$mode.time; rc=$?
     [ $rc = 0 ] && "$C/bin/calibredrv" -a layout filemerge -in "$gds" \
         -infile "{-name $db.gds -placecell {-refcell ${top}_$db -incell $top -x 0 -y 0}}" -out "${top}_fill.gds" > merge.log 2>&1 || rc=1
     for o in "$db.gds:deck.$mode" "${top}_fill.gds:$db.gds"; do
         [ -s "${o%%:*}" ] && ! [ "${o%%:*}" -ot "${o#*:}" ] || { echo "CAL55_FAIL $mode $top: ${o%%:*} missing, empty or older than ${o#*:} (not this run's)"; rc=1; }
     done
     echo "CAL55 $mode $top rc $rc $(grep 'TOTAL DRC Results Generated' "$sum") wall $(grep Elapsed cal_$mode.time | awk '{print $NF}') out $(ls -s "${top}_fill.gds" 2>/dev/null)"
     grep "RULECHECK .* TOTAL Result Count = [1-9]" "$sum" | awk -v m=$mode '{print "CAL55_" m, $2, $(NF-1)}' | head -40 ;;
lvs) src=$4; d=$5; t=${6:-8}; mkdir -p "$d"; cd "$d" || exit 1; L=$K/CRN65GP/TN65CMSP018K1_V1.0C/Calibre/lvs
     sed -e "s#^LAYOUT PRIMARY .*#LAYOUT PRIMARY \"$top\"#" -e "s#^LAYOUT PATH .*#LAYOUT PATH \"$gds\"#" \
         -e "s#^SOURCE PRIMARY .*#SOURCE PRIMARY \"$top\"#" -e "s#^SOURCE PATH .*#SOURCE PATH \"$src\"#" \
         -e "s#^INCLUDE ./DFM/dfm_device#INCLUDE $L/DFM/dfm_device#" ${QB36_LVS_SED:-} "$L/calibre.lvs" > deck.lvs
     [ -n "${QB36_LVS_EXTRA:-}" ] && cat "$QB36_LVS_EXTRA" >> deck.lvs
     cal_edits lvs QB36_LVS_SED QB36_LVS_EXTRA QB36_HCELL
     cal_deck . || exit 1
     hc=""; if [ -n "${QB36_HCELL:-}" ]; then hc="-hcell $QB36_HCELL"; fi
     /usr/bin/time -v "$C/bin/calibre" -lvs -hier $hc -turbo "$t" deck.lvs > cal_lvs.log 2> cal_lvs.time; rc=$?
     echo "CAL36 lvs $top rc $rc wall $(grep Elapsed cal_lvs.time | awk '{print $NF}') rss_kb $(grep Maximum cal_lvs.time | awk '{print $NF}')"
     grep -m4 "CORRECT\|INCORRECT\|NOT COMPARED" lvs.rep; awk '/CELL  SUMMARY/{f=1} f && /INCORRECT|NOT COMPARED/ {print "CAL36_CELL", $0} /LVS PARAMETERS/{f=0}' lvs.rep | head -40
     cal_result lvs "$top" . || res=1; cal_result erc "$top" . || res=1 ;;
check) if [ "$2" = deck ]; then cal_deck "${4:?rundir}"; else cal_result "$2" "$3" "${4:?rundir}"; fi; exit ;;
*) sed -n '2,13p' "$0"; exit 1 ;;
esac
[ $rc = 0 ] || exit $rc     # Calibre's own failure first
exit $res
