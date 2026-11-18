#!/usr/bin/env bash
# R15 hub floorplan variants (results/r15.md), on tau from the snapshot root (as impl/r10b/run.sh, QC_BUILD / QB_SYN / QB9_W):
#   run15.sh fp  <tag>          impl/r10b/run.sh fp with impl/r15/mplace15.py (QB15_FP base|mid|split|gap, QB15_GAP, QB15_NG)
#                               instead of mplace10.py (same steps: sdc.py, init, macro dump, floorplan, pins9.py, pdn)
#                               (QB15_MPLACE: opt-in floorplan script with the same interface, e.g. impl/r22/mplace22.py)
#                               (QB15_PINS: opt-in pin-plan script with the pins9.py interface, e.g. impl/r23/pins23.py)
#   run15.sh grt <tag> <db>     impl/r10b/run.sh grt with impl/r15/grt15.tcl (QB15_GADJ_L per-layer adjustment, opt-in)
#   run15.sh lay <tag> <g>      per y-band / per layer GRT guide demand vs capacity + overflow by y band (lay15.py) -> grt_<g>/lay15.txt
#   run15.sh all <tag>          fp + pnr to place + grt (QB_GI [3], QB_GTAG [pl3]) + r10b ana + lay  (= impl/r12/launch.sh chain)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad; PY=$TOOLS/env/bin/python3
export QB_SYN=${QB_SYN:-r10_rpw}
W=${QB9_W:-$B/r10b_ww}; export QB9_W=$W
R10=$root/qc18bacc/impl/r10b
kit() { . "$root/flow/tsmc65/common/tool.sh"
        QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY; }
step=${1:?step}; tag=${2:?tag}; d=$B/pnr/$tag
case $step in
fp)  kit; mkdir -p "$W/cfg_$tag"
     "$PY" -I "$root/qc18bacc/impl/r9b/sdc.py" "$W/bnd_bits.txt" "${QB9_PER:-1.85}" "$W/cfg_$tag/qb_hub.sdc" "$W/cfg_$tag/hub_io.tcl" || exit 1
     QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$R10/hub.cfg" "$tag" || exit 1
     ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
     "$PY" -I "${QB15_MPLACE:-$here/mplace15.py}" "$d/macros.txt" "$d/mplace.tcl" || exit 1
     x0=$(sed -n 's/^set ::QB9_X0 //p' "$d/mplace.tcl")
     "$PY" -I "${QB15_PINS:-$root/qc18bacc/impl/r9b/pins9.py}" "$W/bnd_bits.txt" "$B/r5b_blk/qb_col_blk.lef" "$x0" "$d/pins9_data.tcl" || exit 1
     QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$root/flow/tsmc65/pnr/run_pnr.sh" "$R10/hub.cfg" "$tag" ;;
grt) kit; cd "$d" || exit 1; g=$d/grt_${QB_GTAG:-a}; mkdir -p "$g"
     QB_DB=${3:-cts} QB_GOUT=$g QC_PNR_OUT=$d /usr/bin/time -v -o "$g/grt.time" "$OR" -no_init -no_splash -exit \
         -log "$g/grt.log" "$here/grt15.tcl" > "$g/grt.out" 2>&1 < /dev/null
     grep -h "^R10B\|^R15" "$g/grt.out"; grep -h "Elapsed\|Maximum res" "$g/grt.time" ;;
lay) g=$d/grt_${3:-pl3}
     python3 -I "$here/lay15.py" "$d/mplace.tcl" "$g/route.guide" "$g/gr_congestion.rpt" "$g/grt.log" > "$g/lay15.txt"; cat "$g/lay15.txt" ;;
all) echo R15_START $(date +%T)
     "$0" fp "$tag" || exit 1
     QC_PNR_TO=place "$R10/run.sh" pnr "$tag"; [ -s "$d/db/place.odb" ] || { echo R15_FAIL place; exit 1; }
     echo R15_PLACED $(date +%T)
     gt=${QB_GTAG:-pl3}
     QB_GI=${QB_GI:-3} QB_GTAG=$gt "$0" grt "$tag" place || exit 1
     echo R15_GRT $(date +%T)
     QB_YS="${QB_YS:-361 1300}" "$R10/run.sh" ana "$tag" "$gt" > /dev/null
     "$0" lay "$tag" "$gt" > /dev/null
     echo R15_DONE $(date +%T) ;;
*) sed -n '2,7p' "$0"; exit 1 ;;
esac
echo "R15_DONE_STEP $step"
