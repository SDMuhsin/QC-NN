#!/usr/bin/env bash
# R28 (results/r28.md): feasible-first hub die ladder.  r26_p1 settings (RTL QB_TOP_PTR=1 netlist r26_ptr / r26_w,
# floorplan pn2 = QB22_FP pn + QB22_S2S 1, max fanout 32, max transition 0.4, post-CTS hook pc24 fix, QB_TNS 10,
# QB_RT_LOOPS 0, QB_IO_LAT 1.30) at a relaxed clock QB9_PER [3.40]; the die grows in height through QB_SB (the
# middle logic band takes the extra height; macros / pins as pn2).  Opt-in density QB28_D sets QB_DENS (= D - 0.03),
# QB_GPL_INCR_DENS and QB9_GPL2_DENS (= D) together (unset: r26_p1 values 0.62 / 0.65 / 0.65).  On tau from the snapshot root:
#   qc18bacc/impl/r28/run28.sh gate <tag>   impl/r22/run.sh gate (fp + place + GRT + budget gate)
#   qc18bacc/impl/r28/run28.sh prod <tag>   impl/r22/run.sh prod from cts (CTS .. post-CTS repair .. GRT + antenna)
#   qc18bacc/impl/r28/run28.sh meas <tag>   impl/r26/run26.sh meas <tag> grt (std area, signal pins)
#   qc18bacc/impl/r28/run28.sh dr|post|ant|abs|fin <tag>   impl/r22/run.sh (post: QB_PT_PERIOD = QB9_PER)
#   qc18bacc/impl/r28/run28.sh all <tag>    gate -> prod -> meas -> dr
set -u
here=$(cd "$(dirname "$0")" && pwd); I=$(cd "$here/.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
export QB_SYN=${QB_SYN:-r26_ptr} QB9_W=${QB9_W:-$B/r26_w} QB22_FP=${QB22_FP:-pn} QB22_S2S=${QB22_S2S:-1}
export QB9_PER=${QB9_PER:-3.40} QB_IO_LAT=${QB_IO_LAT:-1.30} QB_SB=${QB_SB:-649}
export QB_PC_HOOK=${QB_PC_HOOK:-$I/r24/pc24.tcl} QB24_MODE=${QB24_MODE:-fix} QB_TNS=${QB_TNS:-10} QB_RT_LOOPS=${QB_RT_LOOPS:-0}
if [ -n "${QB28_D:-}" ]; then
  export QB_DENS=$(awk "BEGIN{printf \"%.2f\", $QB28_D - 0.03}") QB_GPL_INCR_DENS=$QB28_D QB9_GPL2_DENS=$QB28_D
else
  export QB_GPL_INCR_DENS=${QB_GPL_INCR_DENS:-0.65} QB9_GPL2_DENS=${QB9_GPL2_DENS:-0.65}
fi
export QB_PT_PERIOD=${QB_PT_PERIOD:-$QB9_PER}
step=${1:?step}; tag=${2:?tag}
echo "R28 $step $tag SB $QB_SB PER $QB9_PER IO_LAT $QB_IO_LAT DENS ${QB_DENS:-0.62}/$QB_GPL_INCR_DENS/$QB9_GPL2_DENS $(date +%T)"
case $step in
gate|prod|dr|post|ant|abs|fin) "$I/r22/run.sh" "$step" "$tag" ;;
meas) "$I/r26/run26.sh" meas "$tag" grt ;;
all)  "$0" gate "$tag" && "$0" prod "$tag" && { "$0" meas "$tag"; "$0" dr "$tag"; } ;;
*)    sed -n '2,12p' "$0"; exit 1 ;;
esac
echo "R28_DONE $step $tag $(date +%T)"
