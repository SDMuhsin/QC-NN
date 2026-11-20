#!/usr/bin/env bash
# R31 antenna round 3 on run <tag> (period <per>): seed31.sh (LEF-rule violators of the routed run), std-cell pins of
# it -> R31_SEED; impl/r31/buf31.tcl through the dio hook (macro-input isolation buffers), diodes r31b_dio_*, then
# run31.sh redo (dio -> dr -> fin -> antd -> pt).   qc18bacc/impl/r31/redo2.sh <tag> <per>
set -u
here=$(cd "$(dirname "$0")" && pwd); B=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; tag=${1:?tag}; per=${2:?per}; d=$B/pnr/$tag
"$here/seed31.sh" "$tag"
grep -v "u_mac/" "$d/r31_seed.txt" > "$d/r31_seed_std.txt"; echo "R31_SEED_STD $(wc -l < "$d/r31_seed_std.txt")"
R29_DIO_PFX=r31b_dio_ R31_PDN=$here/buf31.tcl R31_SEED=$d/r31_seed_std.txt R29_HPWL=${R29_HPWL:-1000} "$here/run31.sh" redo "$tag" "$per"
