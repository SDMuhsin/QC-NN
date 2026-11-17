#!/usr/bin/env bash
# R16 (results/r16.md): qb_act2_blk closure on top of impl/r13 / impl/r9a (steps imported, not copied):
#   qc18bacc/impl/r16/run.sh postcts <src> <tag>   CTS checkpoint <src>/db/cts.odb (period 1.85 -> QB_PNR_PERIOD_RT 2.0) ->
#                                                  flow route step with r16/act.cfg: post-CTS re-spread (respread.tcl:
#                                                  QB16_DENS / QB16_DMARGIN / QB16_GPAD / QB16_S1INF), S1 padding, r9a
#                                                  setup / hold repair, db/cts_rt.odb, stop (as impl/r13/postcts.sh)
#   qc18bacc/impl/r16/run.sh dens <tag>            pin-density deciles before / after the re-spread (r13 m2_short.py '-')
#   qc18bacc/impl/r16/run.sh <step> ...            syn | pnr -> impl/r13/run.sh; rt | post | abs -> impl/r9a/run.sh
# R16 recipe: run.sh postcts r13_c1 r16_se with QB16_PEN=0.01 QB16_OVF=0.05 QB16_S1INF=1 (QB_SYN r13_actc, CTS checkpoint
#   of R13's r13_c1); QB9_GR_ADJ=0.05 QB9_GR_ITER=10 QB9_ANT=0 QB_DR_ITER=<n> run.sh rt r16_se <tag> (r16_r_it2: n = 6, stopped
#   after iteration 2, markers flat; r16_d: n = 0, the delivered db); QB_PT_PERIOD=2.0 run.sh post r16_d; run.sh abs r16_d
#   (-> $QC_BUILD/r9a_blk/r16_d)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
export QB_SYN=${QB_SYN:-r13_actc}
step=${1:?step}
case $step in
postcts) src=${2:?src}; tag=${3:?tag}; per=${QB_PNR_PERIOD_RT:-2.0}; d=$B/pnr/$tag
     rm -rf "$d"; mkdir -p "$d/db" "$d/rpt"
     cd "$B/pnr/$src" && cp -r kit.env rc "$d/" && cp db/cts.odb "$d/db/" && grep -v postcts summary.txt > "$d/summary.txt"
     half=$(awk -v p=$per 'BEGIN{print p/2}')
     sed -E "s/(create_clock .*-period )[0-9.]+/\\1$per/; s/-waveform \\{0 [0-9.]+\\}/-waveform {0 $half}/" db/cts.sdc > "$d/db/cts.sdc"
     DW=${QB9_DW:-900}; DH=${QB9_DH:-1970}
     QB13_STOP_RT=1 QC_PNR_FROM=route QB_PNR_PERIOD=$per \
     QB_W=$((DW-10)) QB_H=$((DH-10)) QB7_YOFF=${QB7_YOFF:-$((3110-DH))} QB_IO_LAT=${QB_IO_LAT:-0.55} \
     QC_PNR_THREADS=${QC_PNR_THREADS:-16} QB_DENS=${QB_DENS:-0.55} QB7_MAXTRAN=${QB9_MAXTRAN:-0.30} QB7_MAXFO=${QB9_MAXFO:-32} \
     QB7_DPL_ARGS=${QB9_DPL:-"-max_displacement {200 200}"} QB_CFG=../r16/act.cfg QB_RT_LOOPS=${QB_RT_LOOPS:-1} \
       /usr/bin/time -v -o "$B/pnr_$tag.time" "$root/impl/pnr/run.sh" pnr "$tag"
     ls -la "$d/db/cts_rt.odb" && echo R16_POSTCTS_DONE $tag ;;
dens) d=$B/pnr/${2:?tag}/rpt; py=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3
     for s in pre post; do echo "## $s"; $py -I "$root/impl/r13/m2_short.py" - "$d/r16_cells_$s.txt" 10 | head -${QB16_DL:-25}; done ;;
syn|pnr) exec "$here/../r13/run.sh" "$@" ;;
*)   exec "$root/impl/r9a/run.sh" "$@" ;;
esac
