#!/usr/bin/env bash
# R9b south hub hard block (results/r9b.md), on tau6 from the repository root, QC_BUILD as R8:
#   (env QB_SYN [r8a_rp] netlist, QB9_W [$B/r9b] work dir of the partition, read by hub.cfg)
#   qc18bacc/impl/r9b/run.sh dump            unplaced connectivity dump of syn/$QB_SYN (dump.tcl) + impl/r6a/cuts.py
#                                            groups (--head-south --split-w) -> $B/r9b/grp0.txt
#   qc18bacc/impl/r9b/run.sh part            hub membership (part.py) + DC group (dc_part.tcl, no optimisation)
#   qc18bacc/impl/r9b/run.sh ports           hub-side registration per port (ports.tcl) -> ports_reg.txt
#   qc18bacc/impl/r9b/run.sh sdc             boundary table (bnd.py) -> bnd_bits.txt / bnd_bus.txt
#   qc18bacc/impl/r9b/run.sh fp  <tag>       init, macro dump, mplace9.py (QB_SB / QB_CH), sdc.py (QB9_PER), pins9.py, floorplan + pdn
#   qc18bacc/impl/r9b/run.sh pnr <tag>       place .. global route (QB_GRT_STOP 1: checkpoint grt + exit), hub.cfg env knobs
#   qc18bacc/impl/r9b/run.sh dr  <tag>       detailed route in a fresh process (impl/r8/run.sh dr: dr.tcl, RSS log, SPEF)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad; PY=$TOOLS/env/bin/python3
export QB_SYN=${QB_SYN:-r8a_rp}
W=${QB9_W:-$B/r9b}; export QB9_W=$W; mkdir -p "$W"
kit() { . "$root/flow/tsmc65/common/tool.sh"
        QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY; }
step=${1:?step}
case $step in
dump) kit; cd "$W" || exit 1
     QC_PNR_OUT=$W QB_NETLIST=$B/syn/$QB_SYN/qb_chip.v QB_OUT=$W/dump.txt /usr/bin/time -v -o dump.log.time \
         "$OR" -no_init -no_splash -exit -log dump.log "$here/dump.tcl" > dump.out 2>&1 < /dev/null
     tail -2 dump.out
     python3 -I "$root/qc18bacc/impl/r6a/cuts.py" dump.txt grp --head-south --split-w --groups grp0.txt > cuts.log 2>&1 || { tail -3 cuts.log; exit 1; }
     awk '{n[$2]++} END {for (g in n) print "GROUP_CELLS", g, n[g]}' grp0.txt | sort ;;
part) # impl/r9b/part.py -> hub_cells.txt; DC group (dc_part.tcl) -> qb_chip_r9b.{ddc,v}, qb_hub.v, qb_hub_char.sdc
     kit; cd "$W" || exit 1
     python3 -I "$here/part.py" dump.txt grp0.txt hub > part.log || exit 1; grep -v mixed part.log
     ( set -a; . "$B/syn/$QB_SYN/run.env"; set +a
       QB_SYN_DIR=$B/syn/$QB_SYN QB_W=$W qc_tool dc_part.log dc_shell -f "$here/dc_part.tcl" )
     grep '^R9B' dc_part.log; qc_time dc_part.log
     python3 -I "$here/const.py" qb_hub.v qb_hub_c.v && python3 -I "$here/const.py" qb_chip_r9b.v qb_chip_r9b_c.v ;;
ports) kit; cd "$W" || exit 1     # hub-side registration of every hub port (ports.tcl) -> ports_reg.txt
     QC_PNR_OUT=$W QB_NETLIST=$W/qb_hub_c.v QB_OUT=$W/ports_reg.txt "$OR" -no_init -no_splash -exit -log ports.log "$here/ports.tcl" > ports.out 2>&1 < /dev/null
     tail -1 ports.out ;;
sdc) # $B/r9b/bnd_bits.txt (bnd.py) -> per-run SDC (QB9_PER) + pins data
     cd "$W" && python3 -I "$here/bnd.py" qb_chip_r9b.v qb_hub.v ports_reg.txt bnd && cat bnd_bus.txt | head -30 ;;
fp)  tag=${2:?tag}; d=$B/pnr/$tag; kit; mkdir -p "$W/cfg_$tag"
     "$PY" -I "$here/sdc.py" "$W/bnd_bits.txt" "${QB9_PER:-1.85}" "$W/cfg_$tag/qb_hub.sdc" "$W/cfg_$tag/hub_io.tcl" || exit 1
     QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/hub.cfg" "$tag" || exit 1
     ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
     "$PY" -I "$here/mplace9.py" "$d/macros.txt" "$d/mplace.tcl" || exit 1
     x0=$(sed -n 's/^set ::QB9_X0 //p' "$d/mplace.tcl")
     "$PY" -I "$here/pins9.py" "$W/bnd_bits.txt" "$B/r5b_blk/qb_col_blk.lef" "$x0" "$d/pins9_data.tcl" || exit 1
     QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/hub.cfg" "$tag" ;;
pnr) tag=${2:?tag}; kit
     QB_GRT_STOP=${QB_GRT_STOP:-1} QC_PNR_FROM=${QC_PNR_FROM:-place} "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/hub.cfg" "$tag" ;;
dr)  tag=${2:?tag}; QB8_DR_THREADS=${QB8_DR_THREADS:-12} "$root/qc18bacc/impl/r8/run.sh" dr "$tag" ;;
tcl) tag=${2:?tag}; d=$B/pnr/$tag; kit; cd "$d" || exit 1     # read-only probe: OpenROAD Tcl $3 in run <tag>
     QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit -log probe.log "${3:?tcl}" > probe.out 2>&1 < /dev/null; grep -h "^PG\|^R9B" probe.out ;;
equiv) # pin-level dumps of the r8a_rp and the partitioned chip netlists + equiv.py
     kit; cd "$W" || exit 1
     for x in old new; do
         v=$B/syn/$QB_SYN/qb_chip.v; [ $x = new ] && v=$W/qb_chip_r9b_c.v
         QB_PINS=1 QC_PNR_OUT=$W QB_NETLIST=$v QB_OUT=$W/dump_pins_$x.txt "$OR" -no_init -no_splash -exit -log dump_$x.log "$here/dump.tcl" > dump_$x.out 2>&1 < /dev/null &
     done; wait
     python3 -I "$here/equiv.py" dump_pins_old.txt dump_pins_new.txt change_names.log | tee equiv.txt ;;
*) sed -n '2,12p' "$0"; exit 1 ;;
esac
echo "R9B_DONE $step"
