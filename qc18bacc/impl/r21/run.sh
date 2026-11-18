#!/usr/bin/env bash
# R21 (results/r21.md): south hub qb_hub production at 2.30 ns on the band-450 die (R15 mid floorplan + per-layer GRT
# adjustment), steps imported from impl/r15 / r10b / r9b / r8 (not copied).  On tau from the snapshot root:
#   qc18bacc/impl/r21/run.sh pnr <tag>    fp (impl/r15/run15.sh fp, QB15_FP [mid]) + place (timing driven) .. CTS ..
#                                         post-CTS repair (QB_IO_LAT) .. GRT (QB9_GR_ITER, QB15_GADJ_L) + antenna repair
#                                         (QB21_ANT) -> db/grt.odb (+ db/cts_rt.odb = route input), exit
#   qc18bacc/impl/r21/run.sh rt  <tag>    the same from db/cts.odb (route step only)
#   qc18bacc/impl/r21/run.sh dr  <tag>    detailed route of db/grt.odb (impl/r10b/run.sh dr = impl/r8 dr.tcl + SPEF tt)
#   qc18bacc/impl/r21/run.sh grt <src> <tag>  GRT (grt21.tcl) of <src>/db/cts_rt.odb in a new run <tag> (M5 control), then dr <tag>
#   qc18bacc/impl/r21/run.sh post <tag>   SPEF ss / ff + PT sign-off and ETMs tt / ss / ff (pt_hub.tcl, QB_PT_PERIOD [2.30])
#   qc18bacc/impl/r21/run.sh abs <tag>    abstract LEF (abs.tcl) + ETMs + routed netlist -> $QC_BUILD/r21_<tag>/
#   qc18bacc/impl/r21/run.sh ant <tag>    check_antennas of db/route_dr.odb in its own process (ant.tcl)
#   qc18bacc/impl/r21/run.sh all <tag>    pnr -> dr -> (ant | post -> abs);  fin <tag>: ant | post -> abs
# Env defaults (= r15_midc + B, the R15 DR baseline, plus TD / CTS / repair): QB9_PER 2.30, QB_TD 1, QB_IO_LAT 1.30 (measured p50 hub clock-pin latency after CTS, clk_lat.tcl),
# QB9_GR_ITER 10, QB15_GADJ_L "M5-M9 0.10", QB_MAXTRAN 0.4, QB21_MAXFO (unset = SDC 16), QB_DR_ITER 64.
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad
export QB_SYN=${QB_SYN:-r10_rpw} QB9_W=${QB9_W:-$B/r10b_ww} QB10_SRD=${QB10_SRD:-0}
export QB_SB=${QB_SB:-450} QB15_FP=${QB15_FP:-mid} QB9_PER=${QB9_PER:-2.30} QB_TD=${QB_TD:-1} QB_RD=${QB_RD:-0}
export QB_DPL_ARGS=${QB_DPL_ARGS:-"-max_displacement 500"} QB9_CHBLK=${QB9_CHBLK:-40} QB9_GPL2=${QB9_GPL2:-1}
export QB9_GPL2_DENS=${QB9_GPL2_DENS:-0.80} QB_IO_LAT=${QB_IO_LAT:-1.30} QB_RT_LOOPS=${QB_RT_LOOPS:-1}
export QB9_GR_ITER=${QB9_GR_ITER:-10} QB15_GADJ_L=${QB15_GADJ_L-"M5-M9 0.10"} QB_DR_ITER=${QB_DR_ITER:-64}
export QC_PNR_THREADS=${QC_PNR_THREADS:-16}
SET="QB_GPL_INCR_DENS ${QB_GPL_INCR_DENS:-0.80} PRE_PLACE_TCL $here/place_pre.tcl PRE_ROUTE_TCL $here/route_pre.tcl POST_GRT_TCL $here/post_grt.tcl"
step=${1:?step}; tag=${2:-}; d=$B/pnr/$tag
case $step in
pnr) echo R21_PNR_START $(date +%T)
     "$root/qc18bacc/impl/r15/run15.sh" fp "$tag" || exit 1
     QC_PNR_SET="$SET" QB_GRT_STOP=1 QC_PNR_FROM=place "$root/flow/tsmc65/pnr/run_pnr.sh" "$root/qc18bacc/impl/r10b/hub.cfg" "$tag"
     [ -s "$d/db/grt.odb" ] || { echo R21_FAIL grt; exit 1; }
     echo R21_PNR_DONE $(date +%T) ;;
rt)  echo R21_RT_START $(date +%T)    # restart at the route step (post-CTS repair .. GRT) from db/cts.odb
     QC_PNR_SET="$SET" QB_GRT_STOP=1 QC_PNR_FROM=route QC_PNR_TO=route "$root/flow/tsmc65/pnr/run_pnr.sh" "$root/qc18bacc/impl/r10b/hub.cfg" "$tag"
     [ -s "$d/db/grt.odb" ] || { echo R21_FAIL grt; exit 1; }
     echo R21_RT_DONE $(date +%T) ;;
grt) src=$B/pnr/${2:?src}; tag=${3:?tag}; d=$B/pnr/$tag     # control: GRT (grt21.tcl) of <src>'s route input in run <tag>
     mkdir -p "$d/db" "$d/rpt"
     for f in config.tcl kit.env mplace.tcl macros.txt pins9_data.tcl summary.txt; do cp "$src/$f" "$d/"; done; cp -r "$src/rc" "$d/"
     cp "$src/db/cts_rt.odb" "$src/db/cts_rt.sdc" "$d/db/"
     mkdir -p "$QB9_W/cfg_$tag"; cp "$QB9_W/cfg_${2}/"* "$QB9_W/cfg_$tag/"
     ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$d" && QC_FLOW=$FLOW QC_PNR_OUT=$d QB_GI=$QB9_GR_ITER /usr/bin/time -v -o grt.time "$OR" -no_init -no_splash -exit \
         -log grt.log "$here/grt21.tcl" > grt.out 2>&1 < /dev/null )
     grep -h "r21 grt\|GRT-0096\|Total.*overflow" "$d/grt.log" | tail -5 ;;
dr)  QB_ANT_CHECK=0 QB8_DR_FILL=0 QB8_DR_THREADS=${THR:-16} "$root/qc18bacc/impl/r10b/run.sh" dr "$tag" ;;
ant) ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$d" && QC_FLOW=$FLOW QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit -log ant.log "$here/ant.tcl" > ant.out 2>&1 < /dev/null )
     grep -h "R21_ANT\|Found" "$d/ant.log" ;;
post) # SPEF ss / ff in parallel with PT + ETM tt (tt SPEF comes from the dr step), then PT + ETM ss / ff (4 in parallel);
     # every pt_shell in its own work dir (extract_model writes ./<top>_lib.lib temporaries: impl/r9a/run.sh abs note)
     ptc() { ( . "$root/flow/tsmc65/common/tool.sh"; . "$d/kit.env"; set -a; . "$B/syn/$QB_SYN/run.env"; set +a
               mkdir -p "$d/w_$3_$1"; cd "$d/w_$3_$1" || exit 1
               QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$1 QB21_SDC=$QB9_W/cfg_$tag/qb_hub.sdc QB_PT_PERIOD=${QB_PT_PERIOD:-2.30} QB21_ETM=$2 \
                 qc_tool "$d/$3_$1.log" pt_shell -f "$here/pt_hub.tcl" ) ; }
     for c in ss ff; do QB_SPEF_CORNERS=$c "$root/qc18bacc/impl/pnr/run.sh" spef "$tag" > "$d/spef_$c.out" 2>&1 & done
     ptc tt 0 pt_hub & ptc tt 1 etm & wait
     for c in ss ff; do ptc $c 0 pt_hub & ptc $c 1 etm & done; wait
     for c in tt ss ff; do echo "PT_HUB $c errors $(grep -c '^Error' $d/pt_hub_$c.log) ETM errors $(grep -c '^Error' $d/etm_$c.log)"; cat "$d/pt_hub_$c.txt"; done ;;
abs) o=$B/r21_$tag; mkdir -p "$o"     # LEF (abs.tcl) + copies of the ETMs (post step) and the routed netlist
     ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$d" && QC_FLOW=$FLOW QC_PNR_OUT=$d QB21_ABS_OUT=$o "$OR" -no_init -no_splash -exit -log abs.log "$here/abs.tcl" > abs.out 2>&1 < /dev/null )
     grep "R21_ABS" "$d/abs.log"; python3 -I "$root/qc18bacc/impl/r9a/lef_size.py" "$o/qb_hub.lef" "$d/abs.log"
     cp "$d/out/qb_hub.v" "$d"/out/etm/qb_hub_{tt,ss,ff}.lib "$d"/out/etm/qb_hub_{tt,ss,ff}_lib.db "$o/" 2>/dev/null; ls -la "$o"; echo R21_ABS_DONE ;;
fin) "$0" ant "$tag" > "$d/ant_step.out" 2>&1 & "$0" abs "$tag" > "$d/abs_step.out" 2>&1 & "$0" post "$tag"; wait
     cp "$d"/out/etm/qb_hub_{tt,ss,ff}.lib "$d"/out/etm/qb_hub_{tt,ss,ff}_lib.db "$B/r21_$tag/" 2>/dev/null; ls -la "$B/r21_$tag"
     cat "$d/ant_step.out" "$d/abs_step.out"; echo R21_FIN_DONE $(date +%T) ;;
all) "$0" pnr "$tag" || exit 1; "$0" dr "$tag"; "$0" fin "$tag"; echo R21_ALL_DONE $(date +%T) ;;
*)   sed -n '2,13p' "$0"; exit 1 ;;
esac
