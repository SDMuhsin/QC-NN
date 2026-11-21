# R37 act finish after ECO 4: SPEFs + PT tt/ss (QB7_AOUT 0.25), LEF-rule antenna, abstract + ETMs, antenna data in the LEF, etmcheck
B=/tmp/ckp908/qc18bacc/build; P=$B/pnr; S=/tmp/ckp908/qc18bacc/r35_snap; PY=/tmp/ckp908/tools/env/bin/python3; d=$P/r35_act_c; o=$B/r9a_blk/r35_act_c
cd $S || exit 1
echo "R37_ACTFIN post $(date -u +%T)"; QC_SPEF_UNESC=1 QB_SYN=r35_act QB_PT_PERIOD=6.5 QB_PT_CORNERS="tt ss" QB7_AOUT=0.25 bash qc18bacc/impl/r20/run.sh post r35_act_c
echo "R37_ACTFIN antd $(date -u +%T)"; R29_DB=route_dr R29_TAG=dr bash qc18bacc/impl/r29/or29.sh r35_act_c $S/qc18bacc/impl/r29/antd29.tcl r29_antd.log; grep -h "Found\|R29_ANTD" $d/r29_antd.log | tail -3
echo "R37_ACTFIN abs $(date -u +%T)"; QB7_AOUT=0.25 bash qc18bacc/impl/r35/run35.sh actabs r35_act_c 6.5 | tail -3
echo "R37_ACTFIN blkant $(date -u +%T)"; QB35_AOUT=$o/blkant.txt QB35_ADB=finish bash qc18bacc/impl/r29/or29.sh r35_act_c $S/qc18bacc/impl/r35/blkant.tcl r37_blkant.log
LEF=$(. $d/kit.env; echo $LEF); $PY -I qc18bacc/impl/r35/blkant.py "$LEF" $o/blkant.txt $o/qb_act2_blk.lef $o/qb_act2_blk_ant.lef | tail -3
$PY -I qc18bacc/impl/r5b/lef_ring.py $o/qb_act2_blk_ant.lef $o/qb_act2_blk_ant_ring.lef | tail -2
for c in tt ss ff; do $PY -I qc18bacc/impl/r35/etmcheck.py $o/qb_act2_blk_$c.lib 3.0; done
echo "R37_ACTFIN done $(date -u +%T)"
