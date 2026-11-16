#!/usr/bin/env bash
# R6c full-chip P&R (results/r6c.md), on tau from the repository root, QC_BUILD as R5b / R6b:
#   qc18bacc/impl/r6c/run.sh clone <tag> <src tag> <step>  new run dir <tag> from an R6b / R6c run <src tag> on the same
#                                     host: floorplan / group files + db/<step>.odb (+ pdn, the restart point)
#   qc18bacc/impl/r6c/run.sh pnr   <tag>    QC_PNR_FROM (default place) .. QC_PNR_TO (default finish), impl/r6c/chip.cfg
#   qc18bacc/impl/r6c/run.sh probe <tag> <db> [tcl]   read-only probe (default probe_rows.tcl) on db/<db>.odb
#   qc18bacc/impl/r6c/run.sh dr    <tag>    detailed route + finish in a fresh process from db/grt.odb (QB_GRT_STOP run), + SPEF
#   qc18bacc/impl/r6c/run.sh pt    <tag> [corners]    SPEF + PrimeTime (impl/r5b/run.sh pt, QB_PT_EXTRA impl/r6b/pt_extra.tcl)
#   qc18bacc/impl/r6c/run.sh ptp   <tag>    as pt (tt + ss), with the ss SPEF built in parallel with PrimeTime tt
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad
step=${1:?step}; tag=${2:?tag}; d=$B/pnr/$tag
case $step in
clone) s=$B/pnr/${3:?src}; st=${4:?step}; mkdir -p "$d/db" "$d/rpt" || exit 1
     for f in mplace.tcl mplace.tcl.groups grp.txt grp_S_L.pos grp_WA_L.pos grp_W_L.pos grp_N_L.pos grp_S.pos grp_WA.pos grp_W.pos grp_N.pos macros.txt; do
         [ -f "$s/$f" ] && cp "$s/$f" "$d/"; done
     cp -r "$s/rc" "$d/" 2>/dev/null
     for x in pdn $st; do cp "$s/db/$x.odb" "$s/db/$x.sdc" "$d/db/"; done
     : > "$d/summary.txt"; echo "cloned from $s ($st)" > "$d/CLONE" ;;
pnr) QC_PNR_FROM=${QC_PNR_FROM:-place} "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/chip.cfg" "$tag" ;;
probe) cd "$d" || exit 1
     QB_RUN=$d QB_DB=${3:?db} "$OR" -no_init -no_splash -exit "$here/${4:-probe_rows.tcl}" < /dev/null ;;
dr)  . "$root/flow/tsmc65/common/tool.sh"; cd "$d" || exit 1
     QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$TOOLS/env/bin/python3 QC_PNR_OUT=$d QC_BUILD=$B
     /usr/bin/time -v -o dr.log.time "$OR" -no_init -no_splash -exit -log dr.log "$here/dr.tcl" > dr.out 2>&1 < /dev/null
     echo "DR rc $? errors $(grep -c '^\[ERROR' dr.log)"; . ./kit.env
     for c in $CORNERS; do
         "$QC_PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_$c.spef" > "def2spef_$c.log" 2>&1 || echo "def2spef $c failed"
         "$QC_PY" -I "$FLOW/pnr/py/def2spef.py" "out/$TOP.def" "out/$TOP.conn" "rc/$c.txt" "out/${TOP}_${c}_pt.spef" --escape-divider >> "def2spef_$c.log" 2>&1 || echo "def2spef $c (pt) failed"
     done
     drc=$(grep -c 'violation type' rpt/drt.drc.rpt 2>/dev/null); ant=$(sed -n 's/.*Found \([0-9]*\) net violations.*/\1/p' dr.log | tail -1)
     antp=$(sed -n 's/.*Found \([0-9]*\) pin violations.*/\1/p' dr.log | tail -1)
     echo "dr drc_violations ${drc:-NA} antenna_net_violations ${ant:-NA} antenna_pin_violations ${antp:-NA} $(qc_time dr.log)" | tee -a summary.txt ;;
ptp) # as pt, but the ss SPEF (def2spef) runs in parallel with PrimeTime tt, then PrimeTime ss (impl/r5b/pt_chip.tcl)
     QB_SPEF_CORNERS=ss "$root/qc18bacc/impl/pnr/run.sh" spef "$tag" > "$d/spef_ss.out" 2>&1 &
     sp=$!
     . "$root/flow/tsmc65/common/tool.sh"; . "$d/kit.env"
     set -a; . "$(dirname "$NETLIST")/run.env"; set +a; cd "$d" || exit 1
     export QC_SDC=$root/qc18bacc/impl/r4/constraints.sdc QC_PT_HOOK= QC_PERIOD=${QB_PT_PERIOD:-2.0}
     export QB_PT_EXTRA=${QB_PT_EXTRA-$root/qc18bacc/impl/r6b/pt_extra.tcl}
     for c in tt ss; do
         [ $c = ss ] && wait $sp
         QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c QB_BLK=$B/r5b_blk qc_tool "pt_chip_$c.log" pt_shell -f "$root/qc18bacc/impl/r5b/pt_chip.tcl"
         echo "PT_CHIP $c errors $(grep -c '^Error' pt_chip_$c.log)"; cat "pt_chip_$c.txt"
     done ;;
pt)  QB_PT_EXTRA=${QB_PT_EXTRA-$root/qc18bacc/impl/r6b/pt_extra.tcl} "$root/qc18bacc/impl/r5b/run.sh" pt "$tag" ${3:-tt ss} ;;
*) sed -n '2,10p' "$0"; exit 1 ;;
esac
echo "R6C_DONE $step $tag"
