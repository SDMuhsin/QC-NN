#!/usr/bin/env bash
# R19 (results/r19.md): qb_act2_blk with QB_ACT_S1P (band-partitioned S1) on top of impl/r13 / impl/r16 / impl/r9a
# (steps imported, not copied):
#   qc18bacc/impl/r19/run.sh syn                 impl/r13/run.sh syn with QB13_FL = ../r19/qb_act2_blk_chip_s1p.f,
#                                                QB_SYN default r19_s1p (chip-cone wrapper + RPL + S1P)
#   qc18bacc/impl/r19/run.sh pnr <tag>           as impl/r13/run.sh pnr (same env defaults) with QB_CFG = r19/act.cfg
#                                                (band seed before gpl, impl/r19/place.tcl); QB13_PINS=1 (chip pins)
#   qc18bacc/impl/r19/run.sh <step> ...          postcts -> impl/r16/run.sh (re-spread + post-CTS repair); rt | post | abs
#                                                -> impl/r9a/run.sh (via r16)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
export QB_SYN=${QB_SYN:-r19_s1p}
step=${1:?step}
case $step in
syn) QB13_FL=../r19/qb_act2_blk_chip_s1p.f exec "$root/impl/r13/run.sh" syn ;;
pnr) tag=${2:?tag}; export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; DW=${QB9_DW:-900}; DH=${QB9_DH:-1970}
     QB13_PINS=${QB13_PINS:-1} \
     QB_W=$((DW-10)) QB_H=$((DH-10)) QB7_YOFF=${QB7_YOFF:-$((3110-DH))} \
     QB_IO_LAT=${QB_IO_LAT:-0.55} QC_PNR_THREADS=${QC_PNR_THREADS:-16} QB_DENS=${QB_DENS:-0.55} \
       QB7_MAXTRAN=${QB9_MAXTRAN:-0.30} QB7_MAXFO=${QB9_MAXFO:-32} QB7_DPL_ARGS=${QB9_DPL:-"-max_displacement {200 200}"} \
       QB_CFG=../r19/act.cfg QB_PNR_PERIOD=${QB_PNR_PERIOD:-1.85} QB_RT_LOOPS=${QB_RT_LOOPS:-1} QB_DR_ITER=${QB_DR_ITER:-30} \
       /usr/bin/time -v -o "$QC_BUILD/pnr_$tag.time" "$root/impl/pnr/run.sh" pnr "$tag" ;;
*)   exec "$root/impl/r16/run.sh" "$@" ;;
esac
