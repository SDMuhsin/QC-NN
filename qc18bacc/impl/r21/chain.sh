#!/usr/bin/env bash
# R21 tau-side chain after the pnr step: wait for db/grt.odb of run <tag>, pick the DR end iteration from the time left
# to the deadline (QB21_DEADLINE, epoch s; DR must end QB21_POST_H [1.3] h before it for SPEF / PT / ETM / LEF) using the
# per-iteration elapsed profile of the R15 PI DR of r15_midc (cumulative h after iterations 0..14, incl. pin access),
# then dr -> fin.  usage: chain.sh <tag>   (QB_DR_ITER set in the env overrides the pick)
t=${1:?tag}; here=$(cd "$(dirname "$0")" && pwd); B=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; d=$B/pnr/$t
until [ -s "$d/db/grt.odb" ] && ! pgrep -f "run.sh (pnr|rt) $t" > /dev/null; do
    pgrep -f "run.sh (pnr|rt) $t" > /dev/null || [ -s "$d/db/grt.odb" ] || { echo R21C_NO_GRT; exit 1; }; sleep 30; done
left=$(awk -v dl=${QB21_DEADLINE:?} -v now=$(date +%s) -v p=${QB21_POST_H:-1.3} 'BEGIN{print (dl - now) / 3600.0 - p}')
n=$(awk -v h=$left 'BEGIN{split("0.65 1.05 1.43 3.12 4.63 5.77 6.69 7.51 8.26 8.94 9.42 9.86 10.3 10.76 11.18",c," "); n=0; for(i=1;i<=15;i++) if (c[i] <= h) n=i-1; print n}')
n=${QB_DR_ITER:-$n}
echo "R21C_DR $(date +%T) hours_left $left end_iter $n"
QB_DR_ITER=$n "$here/run.sh" dr "$t"
echo "R21C_DR_DONE $(date +%T) $(grep -c 'violation type' $d/rpt/drt.drc.rpt)"
"$here/run.sh" fin "$t"
echo "R21C_DONE $(date +%T)"
