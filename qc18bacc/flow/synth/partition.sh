#!/usr/bin/env bash
# Hub partition of the chip DC netlist (results/r9b.md, r10b.md, r26.md): $QB9_W gets the hub netlist and the boundary
# tables the hub P&R reads (qb_hub_c.v, qb_chip_r9b_c.v, bnd_bits.txt, ...).
#   qc18bacc/flow/synth/partition.sh <syn tag> <work dir>     steps dump part ports sdc:
#     dump   unplaced connectivity of syn/<tag>/qb_chip.v (part_dump.tcl) + part_cuts.py groups (--head-south --split-w) -> grp0.txt
#     part   hub membership (part_hub.py) + DC group (part_dc.tcl, no optimisation) -> qb_chip_r9b.{ddc,v}, qb_hub.v; constants (part_const.py)
#     ports  hub-side registration per port (part_ports.tcl) -> ports_reg.txt
#     sdc    boundary table (part_bnd.py) -> bnd_bits.txt / bnd_bus.txt
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../common/env.sh"
export QB_SYN=${1:?syn tag}; W=${2:?work dir}; export QB9_W=$W; mkdir -p "$W"
for step in ${QB_PART_STEPS:-dump part ports sdc}; do
echo "== $step $(date +%T)"
case $step in
dump) qb_kit; cd "$W" || exit 1
     QC_PNR_OUT=$W QB_NETLIST=$B/syn/$QB_SYN/qb_chip.v QB_OUT=$W/dump.txt /usr/bin/time -v -o dump.log.time \
         "$OR" -no_init -no_splash -exit -log dump.log "$here/part_dump.tcl" > dump.out 2>&1 < /dev/null
     tail -2 dump.out
     python3 -I "$here/part_cuts.py" dump.txt grp --head-south --split-w --groups grp0.txt > cuts.log 2>&1 || { tail -3 cuts.log; exit 1; }
     awk '{n[$2]++} END {for (g in n) print "GROUP_CELLS", g, n[g]}' grp0.txt | sort ;;
part) qb_kit; cd "$W" || exit 1
     python3 -I "$here/part_hub.py" dump.txt grp0.txt hub > part.log || exit 1; grep -v mixed part.log
     ( set -a; . "$B/syn/$QB_SYN/run.env"; set +a
       QB_SYN_DIR=$B/syn/$QB_SYN QB_W=$W qc_tool dc_part.log dc_shell -f "$here/part_dc.tcl" )
     grep '^R9B' dc_part.log; qc_time dc_part.log
     python3 -I "$here/part_const.py" qb_hub.v qb_hub_c.v && python3 -I "$here/part_const.py" qb_chip_r9b.v qb_chip_r9b_c.v ;;
ports) qb_kit; cd "$W" || exit 1
     QC_PNR_OUT=$W QB_NETLIST=$W/qb_hub_c.v QB_OUT=$W/ports_reg.txt "$OR" -no_init -no_splash -exit -log ports.log "$here/part_ports.tcl" > ports.out 2>&1 < /dev/null
     tail -1 ports.out ;;
sdc) cd "$W" && python3 -I "$here/part_bnd.py" qb_chip_r9b.v qb_hub.v ports_reg.txt bnd && cat bnd_bus.txt | head -30 ;;
esac || { echo "PART_FAIL $step"; exit 1; }
done
echo "PART_DONE $QB_SYN $W"
