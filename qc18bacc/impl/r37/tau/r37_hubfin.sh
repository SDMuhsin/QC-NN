# R37 hub finish after the ECO: fin (abs, SPEF ss/ff, PT, ETMs tt/ss/ff), LEF-rule antenna, sign-off PT (pt37), antenna data, etmcheck
B=/tmp/ckp908/qc18bacc/build; P=$B/pnr; S=/tmp/ckp908/qc18bacc/r35_snap; PY=/tmp/ckp908/tools/env/bin/python3; d=$P/r35_hubC; o=$B/r22_r35_hubC
cd $P; until grep -q "R35_DONE hold r35_hubC" r37_hubeco6.out; do sleep 20; done
cd $S || exit 1
echo "R37_HUBFIN fin $(date -u +%T)"; bash qc18bacc/impl/r34/run34.sh fin r35_hubC 6.5 > $P/r37_hubfin_fin.out 2>&1; tail -4 $P/r37_hubfin_fin.out
echo "R37_HUBFIN antd+pt37 $(date -u +%T)"
bash qc18bacc/impl/r34/run34.sh antd r35_hubC 6.5 > $P/r37_hubfin_antd.out 2>&1 &
for c in tt ss; do QB_PT_PERIOD=6.5 QB37_LAT=p50 QB37_FT=1 QB37_VIOL=1 QB37_FR="actout 0.26" bash qc18bacc/impl/r37/pt37.sh r35_hubC $c > $P/r37_hubfin_pt_$c.out 2>&1 & done; wait
tail -3 $P/r37_hubfin_antd.out; for c in tt ss; do grep "^R37\|violating\|slack_ns" $P/r37_hubfin_pt_$c.out | cut -c1-200; done
echo "R37_HUBFIN blkant $(date -u +%T)"; QB35_AOUT=$o/blkant.txt QB35_ADB=finish bash qc18bacc/impl/r29/or29.sh r35_hubC $S/qc18bacc/impl/r35/blkant.tcl r37_blkant.log
LEF=$(. $d/kit.env; echo $LEF); $PY -I qc18bacc/impl/r35/blkant.py "$LEF" $o/blkant.txt $o/qb_hub.lef $o/qb_hub_ant.lef | tail -3
$PY -I qc18bacc/impl/r5b/lef_ring.py $o/qb_hub_ant.lef $o/qb_hub_ant_ring.lef | tail -2
for c in tt ss ff; do $PY -I qc18bacc/impl/r35/etmcheck.py $o/qb_hub_$c.lib 3.0; done
echo "R37_HUBFIN done $(date -u +%T)"
