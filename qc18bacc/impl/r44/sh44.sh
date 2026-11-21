#!/usr/bin/env bash
# R44: run an OR tcl against a read-only run via a shadow dir in /tmp/ckp908/qc18bacc/r44/<tag>   sh44.sh <tag> <tcl> <log> [db...]
set -u
B=/tmp/ckp908/qc18bacc/build; R=/tmp/ckp908/qc18bacc/r44; tag=$1; scr=$2; log=$3; shift 3
src=$B/pnr/$tag; d=$R/sh_$tag; mkdir -p $d/db $d/rc
cp -n $src/config.tcl $src/kit.env $d/ 2>/dev/null; cp -rn $src/rc/. $d/rc/; for f in mplace.tcl pins9_data.tcl macros.txt; do [ -e $src/$f ] && cp -n $src/$f $d/; done
for s in "$@"; do ln -sf $src/db/$s.odb $d/db/$s.odb; ln -sf $src/db/$s.sdc $d/db/$s.sdc; done
root=/tmp/ckp908/qc18bacc/r35_snap; FLOW=$root/flow/tsmc65
export QC_BUILD=$B QB9_W=${QB9_W:-$B/r26_w} QB_SYN=${QB_SYN:-r26_ptr}
. "$root/flow/tsmc65/common/tool.sh"; cd "$d" || exit 1
QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=/tmp/ckp908/tools/env/bin/python3 QC_PNR_OUT=$d QC_FLOW=$FLOW
/usr/bin/time -v /tmp/ckp908/tools/env/bin/openroad -no_init -no_splash -exit -log "$log" "$scr" > "$log.out" 2> "$log.time" < /dev/null
echo SH44_DONE $tag $(date +%T)
