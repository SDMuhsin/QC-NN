#!/usr/bin/env bash
# P&R of the qc18bacc compute core alone (results/pnr_core.md), on the build host from the repository root of the
# host-local tree (/tmp/$USER/qc18bacc/repo), QC_BUILD default /tmp/$USER/qc18bacc/build:
#   qc18bacc/impl/pnr/run.sh pnr <tag>   flow/tsmc65/pnr/run_pnr.sh core.cfg or $QB_CFG (slice.cfg: results/pnr_slice.md) (QC_PNR_TO etc.; QB_TOP,
#                                        QB_SYN, QB_UTIL, QB_DENS, QB_DR_ITER: core.cfg knobs)
#   qc18bacc/impl/pnr/run.sh est <tag>   grt_est.tcl: post-CTS / post-GRT timing at OpenROAD estimates (QB_GRT 0: CTS only)
#   qc18bacc/impl/pnr/run.sh spef <tag>  def2spef (PrimeTime copy) for QB_SPEF_CORNERS (default ss; P&R corners: tt)
#   qc18bacc/impl/pnr/run.sh pt  <tag>   PrimeTime with the def2spef SPEF (pt_post_core.tcl), corners QB_PT_CORNERS (tt ss)
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build} QC_PNR_THREADS=${QC_PNR_THREADS:-14}
step=${1:-}; tag=${2:?tag}
dir=$QC_BUILD/pnr/$tag
case $step in
pnr) "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/${QB_CFG:-core.cfg}" "$tag" ;;
est) . "$root/flow/tsmc65/common/tool.sh"
     export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
     ( cd "$dir" && QC_FLOW=$root/flow/tsmc65 QC_PNR_OUT=$dir QC_PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3 \
         /usr/bin/time -v -o est.time "${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad" -no_init -no_splash -exit \
         -log est.log "$here/grt_est.tcl" > est.out 2>&1 < /dev/null ); echo "EST_DONE $tag rc $?" ;;
spef) # def2spef of the routed DEF for corners outside the P&R corners (QB_SPEF_CORNERS, default ss)
     . "$root/flow/tsmc65/common/tool.sh"; . "$dir/kit.env"; cd "$dir" || exit 1
     export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
     py=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3
     for c in ${QB_SPEF_CORNERS:-ss}; do
         cap=$(QC_FLOW=$FLOW tclsh <<<"proc qc_env {n {d {}}} {return \$d}; source $FLOW/site/site.tcl; source $FLOW/site/pnr.tcl; puts \$::QC_PNR_CAPDIR/\$::QC_PNR_CAPTABLE($c)")
         [ -f rc/$c.txt ] || "$py" -I "$FLOW/pnr/py/captable_rc.py" "$LEF" "$cap" $c rc/$c
         "$py" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_${c}_pt.spef" \
             --escape-divider > "def2spef_$c.log" 2>&1; echo "SPEF_DONE $c rc $? $(ls -la out/${TOP}_${c}_pt.spef | awk '{print $5}')"
     done ;;
pt)  . "$root/flow/tsmc65/common/tool.sh"; . "$dir/kit.env"
     set -a; . "$(dirname "$NETLIST")/run.env"; set +a; cd "$dir" || exit 1
     [ -n "${QB_PT_PERIOD:-}" ] && export QC_PERIOD=$QB_PT_PERIOD      # pnr_slice2.md: DC margin run, sign-off period
     export QC_SDC=$root/qc18bacc/impl/constraints.sdc QC_PT_HOOK=
     for c in ${QB_PT_CORNERS:-tt ss}; do
         QC_PNR_OUT=$dir QC_TOP=$TOP QC_CORNER=$c QC_SDC_FILE=$SDC qc_tool "pt_post_$c.log" pt_shell -f "$here/pt_post_core.tcl"
         echo "PT_POST_DONE $tag $c errors $(grep -c "^Error" "pt_post_$c.log")"; cat "pt_post_$c.txt"
     done ;;
*) sed -n '2,8p' "$0"; exit 1 ;;
esac
