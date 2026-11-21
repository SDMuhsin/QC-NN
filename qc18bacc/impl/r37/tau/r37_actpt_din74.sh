# act PT 6.5 tt/ss with the s_q budget re-split (QB7_DIN 0.74) on the final act; outputs saved aside, summary files restored
B=/tmp/ckp908/qc18bacc/build/pnr; d=$B/r35_act_c; cd /tmp/ckp908/qc18bacc/r35_snap
for c in tt ss; do cp -p $d/pt_blk_$c.txt $d/r37_din74/pt_blk_${c}_aout25.txt; done
QC_SPEF_UNESC=1 QB_SYN=r35_act QB_PT_PERIOD=6.5 QB_PT_CORNERS="tt ss" QB7_AOUT=0.25 QB7_DIN=0.74 bash qc18bacc/impl/r9a/run.sh post r35_act_c
for c in tt ss; do cp -p $d/pt_blk_$c.txt $d/r37_din74/pt_blk_${c}_din74.txt; done
