#!/usr/bin/env bash
# R31: diode seed from the LEF-rule antenna check of a routed run: impl/r29/antd29.tcl (R29_DB [route_dr]) verbose on the
# nets of rpt/r29_antd_dr.rpt; every pin whose LEF-rule block has a VIOLATED line -> <run>/r31_seed.txt (dio29 R29_SEED).
#   qc18bacc/impl/r31/seed31.sh <tag>
set -u
here=$(cd "$(dirname "$0")" && pwd); I=$(cd "$here/.." && pwd)
B=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; tag=${1:?tag}; d=$B/pnr/$tag
nets=$(sed -n 's/^Net: \(\S*\).*/\1/p' "$d/rpt/r29_antd_dr.rpt" | sort -u | tr '\n' ' ')
R29_DB=${R29_DB:-route_dr} R29_TAG=sv R29_NETS="$nets" "$I/r29/or29.sh" "$tag" "$I/r29/antd29.tcl" r31_seed.log > /dev/null
# the verbose blocks after the last "R29_ANTD M8 scalar" line are the LEF-rule ones
awk '/R29_ANTD M8 scalar/{s=1; next} s && /^  Pin: /{p=$2} s && /VIOLATED/ && p!=""{print p}' "$d/r31_seed.log" | sort -u > "$d/r31_seed.txt"
echo "R31_SEED $tag nets $(echo $nets | wc -w) pins $(wc -l < "$d/r31_seed.txt"): $(head -8 "$d/r31_seed.txt" | tr '\n' ' ')"
