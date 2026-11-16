#!/bin/bash
# R12 analysis of one run (on tau): dumps (q1dump.tcl init + grt_pl3, q3dump.tcl) then q1 / q2 / q3 / q3b -> <out>
# usage: ana12.sh <run tag> <out dir> [ybot 1300.6]
t=$1; o=$2; yb=${3:-1300.6}
B=/tmp/ckp908/qc18bacc/build; D=$B/pnr/$t; S=/tmp/ckp908/qc18bacc/r10b_snap/qc18bacc/impl; P=/tmp/ckp908/qc18bacc/r10b_probe.sh
mkdir -p $o
$P $D $S/r12/q1dump.tcl $o/q1dump.out &
$P $D $S/r12/q1dump.tcl $o/q1dump_init.out QB_DB=init QB12_OUT=$D/rpt/r12_dump_init.txt &
$P $D $S/r12/q3dump.tcl $o/q3dump.out &
wait
H=$(sed -n 's/^set ::QB9_H //p' $D/mplace.tcl)
python3 -I $S/r12/q1.py $D/rpt/r12_dump_init.txt $D/rpt/r12_dump.txt $D/rpt/dumpdb.txt $D/grt_pl3/netcls2.txt $S/r10b/ovf10.py $o > /dev/null
python3 -I $S/r12/q2.py $D/rpt/r12_dump.txt $D/rpt/dumpdb.txt $D/grt_pl3/gr_congestion.rpt $yb $o > /dev/null
python3 -I $S/r12/q3.py $D/rpt/r12_obs.txt $D/grt_pl3/route.guide $D/grt_pl3/grt.log $D/rpt/r12_dump.txt $D/rpt/dumpdb.txt $yb $o 0.25 $H $D/grt_pl3/gr_congestion.rpt > /dev/null
QB12_H=$H python3 -I $S/r12/q3b.py $D/grt_pl3/route.guide $o/q3_layers.txt $D/rpt/dumpdb.txt $D/rpt/r12_dump_init.txt $yb $o $D/grt_pl3/netcls2.txt $S/r10b/ovf10.py > /dev/null
echo R12_ANA_DONE $t
