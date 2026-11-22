#!/usr/bin/env bash
# Calibre sign-off runs with the kit decks (results/r36.md, r38.md; decks copied per run with LAYOUT / SOURCE substituted):
#   qc18bacc/flow/signoff/calibre/cal.sh drc <gds> <topcell> <rundir> [turbo=8]   CLN65S_9M_6X2Z.23a (MAIN_DRC_TopMz), hierarchical
#   qc18bacc/flow/signoff/calibre/cal.sh ant <gds> <topcell> <rundir> [turbo=8]   CN65S_9M.ANT.23a
#   qc18bacc/flow/signoff/calibre/cal.sh lvs <gds> <topcell> <src.spi> <rundir> [turbo=8]  CRN65GP calibre.lvs (src.spi must include the cell spice)
# env: QB36_DRC_SED / QB36_LVS_SED = extra sed arguments for the deck copy (e.g. "-f drc_blk.sed"), QB36_LVS_EXTRA,
#      QB36_HCELL (hcell file)
# Summary: grep of the TOTAL counts and the rule checks with results (CAL36 lines).
set -u
C=/CMC/tools/siemens/calibre/aok_cal_2026.1_26.19/aok_cal_2026.1_26.19
export CALIBRE_HOME=$C MGC_HOME=$C MGLS_LICENSE_FILE=${MGLS_LICENSE_FILE:-6056@engrcmc2.usask.ca}
K=/CMC/kits/tsmc_65nm
mode=${1:?drc|ant|lvs}; gds=$2; top=$3
case $mode in
drc|ant) d=$4; t=${5:-8}; mkdir -p "$d"; cd "$d" || exit 1
     [ $mode = drc ] && deck=$K/CLN65GP/DRC/MAIN_DRC_TopMz/CLN65S_9M_6X2Z.23a || deck=$K/CLN65GP/DRC/ANTENNA_DRC/CN65S_9M.ANT.23a
     sed -e "s#^\(LAYOUT PATH\) .*#\1 \"$gds\"#" -e "s#^\(LAYOUT PRIMARY\) .*#\1 \"$top\"#" \
         -e "s#^DRC MAXIMUM RESULTS ALL#DRC MAXIMUM RESULTS 1000#" ${QB36_DRC_SED:-} "$deck" > deck.$mode
     /usr/bin/time -v "$C/bin/calibre" -drc -hier -turbo "$t" deck.$mode > cal_$mode.log 2> cal_$mode.time
     rep=$(sed -n 's/^DRC SUMMARY REPORT "\(.*\)".*/\1/p' deck.$mode | head -1)
     echo "CAL36 $mode $top rc $? $(grep 'TOTAL DRC Results Generated' "$rep") wall $(grep Elapsed cal_$mode.time | awk '{print $NF}') rss_kb $(grep Maximum cal_$mode.time | awk '{print $NF}')"
     grep "RULECHECK .* TOTAL Result Count = [1-9]" "$rep" | awk '{print "CAL36_RULE", $2, $(NF-1)}' | head -60 ;;
lvs) src=$4; d=$5; t=${6:-8}; mkdir -p "$d"; cd "$d" || exit 1; L=$K/CRN65GP/TN65CMSP018K1_V1.0C/Calibre/lvs
     sed -e "s#^LAYOUT PRIMARY .*#LAYOUT PRIMARY \"$top\"#" -e "s#^LAYOUT PATH .*#LAYOUT PATH \"$gds\"#" \
         -e "s#^SOURCE PRIMARY .*#SOURCE PRIMARY \"$top\"#" -e "s#^SOURCE PATH .*#SOURCE PATH \"$src\"#" \
         -e "s#^INCLUDE ./DFM/dfm_device#INCLUDE $L/DFM/dfm_device#" ${QB36_LVS_SED:-} "$L/calibre.lvs" > deck.lvs
     [ -n "${QB36_LVS_EXTRA:-}" ] && cat "$QB36_LVS_EXTRA" >> deck.lvs
     hc=""; if [ -n "${QB36_HCELL:-}" ]; then hc="-hcell $QB36_HCELL"; fi
     /usr/bin/time -v "$C/bin/calibre" -lvs -hier $hc -turbo "$t" deck.lvs > cal_lvs.log 2> cal_lvs.time
     echo "CAL36 lvs $top wall $(grep Elapsed cal_lvs.time | awk '{print $NF}') rss_kb $(grep Maximum cal_lvs.time | awk '{print $NF}')"
     grep -m4 "CORRECT\|INCORRECT\|NOT COMPARED" lvs.rep; awk '/CELL  SUMMARY/{f=1} f && /INCORRECT|NOT COMPARED/ {print "CAL36_CELL", $0} /LVS PARAMETERS/{f=0}' lvs.rep | head -40 ;;
esac
