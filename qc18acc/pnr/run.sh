#!/usr/bin/env bash
# P&R of QC18-ACC v2 on the build host (from the repository root of the host-local tree /tmp/$USER/qc18acc/repo):
#   qc18acc/pnr/run.sh pnr [tag]   OpenROAD (flow/tsmc65/pnr/run_pnr.sh qc18acc/pnr/qa.cfg) -> $QC_BUILD/pnr/<tag>
#   qc18acc/pnr/run.sh pt  [tag]   PrimeTime post-route timing with the def2spef SPEF (pt_post_qa.tcl), ss tt (QA_PT_CORNERS)
#   qc18acc/pnr/run.sh route [tag] v4: global / detailed route in separate processes (route_split.tcl) after
#                                  "QC_PNR_TO=cts run.sh pnr", then the flow's finish + SPEF / STA steps
# tag: qa_pnr.  QC_BUILD default /tmp/$USER/qc18acc/build (synthesis qa2_w3.3 under syn/), QC_PNR_THREADS 14.
# Env passes through to run_pnr.sh (QC_PNR_FROM / _TO / _SET / _POST) and macro_place.tcl (QA_BAND).
# QA_V=3: the v3 design (qa3.cfg: netlist qa3_w3.3, macro_place3.tcl); default v2 (qa.cfg).  QA_CFG: another config
# (qa3b.cfg / qab.cfg: the improved recipes of results/pnr_v3.md).  QA_V=4: qa4.cfg (v4, netlist qa4_w3.3, macro_place4.tcl).
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18acc/build} QC_PNR_THREADS=${QC_PNR_THREADS:-14}
step=${1:-}; tag=${2:-qa_pnr}
case $step in
pnr) cfg=$here/qa.cfg; [ "${QA_V:-2}" = 3 ] && cfg=$here/qa3.cfg; [ "${QA_V:-2}" = 4 ] && cfg=$here/qa4.cfg; [ -n "${QA_CFG:-}" ] && cfg=$(cd "$(dirname "$QA_CFG")" && pwd)/$(basename "$QA_CFG")
     "$root/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag" ;;
route) # v4: the route step split into processes (route_split.tcl: grt, then drt without STA), then the flow's
     # finish step + SPEF / STA post steps; run after "pnr" with QC_PNR_TO=cts (same QA_CFG / QC_PNR_SET)
     cfg=$here/qa.cfg; [ "${QA_V:-2}" = 3 ] && cfg=$here/qa3.cfg; [ "${QA_V:-2}" = 4 ] && cfg=$here/qa4.cfg; [ -n "${QA_CFG:-}" ] && cfg=$(cd "$(dirname "$QA_CFG")" && pwd)/$(basename "$QA_CFG")
     dir=$QC_BUILD/pnr/$tag; . "$root/flow/tsmc65/common/tool.sh"
     export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
     for part in grt drt; do
         ( cd "$dir" && QC_FLOW=$FLOW QC_PNR_OUT=$dir QA_PART=$part /usr/bin/time -v -o route_$part.time \
             "${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad" -no_init -no_splash -exit -log route_$part.log \
             "$here/route_split.tcl" > route_$part.out 2>&1 < /dev/null )
         echo "SPLIT_DONE $part rc $?" >> "$dir/route_$part.out"; tail -1 "$dir/route_$part.out"
         [ -s "$dir/db/route.odb" ] || [ $part = grt ] || exit 1
     done
     QC_PNR_FROM=finish "$root/flow/tsmc65/pnr/run_pnr.sh" "$cfg" "$tag" ;;
pt)  # flow/tsmc65/pnr/run_pt_post.sh with pt_post_qa.tcl (fmax lines, reg2reg, clock latency / skew)
     . "$root/flow/tsmc65/common/tool.sh"; dir=$QC_BUILD/pnr/$tag; . "$dir/kit.env"
     set -a; . "$(dirname "$NETLIST")/run.env"; set +a; cd "$dir" || exit 1
     export QA_SDC_BASE=${QA_SDC_BASE:-$root/qc18acc/impl/constraints.sdc}   # v4: impl/v4/constraints.sdc sources it
     for c in ${QA_PT_CORNERS:-ss tt}; do
         QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c QC_SDC_FILE=$SDC qc_tool "pt_post_$c.log" pt_shell -f "$here/pt_post_qa.tcl"
         echo "PT_POST_DONE $tag $c errors $(grep -c "^Error" "pt_post_$c.log")"; cat "pt_post_$c.txt"
     done ;;
*) sed -n '2,9p' "$0"; exit 1 ;;
esac
