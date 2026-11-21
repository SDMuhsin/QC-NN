#!/usr/bin/env bash
# R44 CTS arm on a copy of r35_hubC place.odb:  arm44.sh <arm> [split_gap]
set -u
B=/tmp/ckp908/qc18bacc/build; R=/tmp/ckp908/qc18bacc/r44; arm=$1; gap=${2:-0}
src=$B/pnr/r35_hubC; d=$R/arm_$arm; rm -rf $d; mkdir -p $d/db $d/rc $d/rpt
cp $src/config.tcl $src/mplace.tcl $src/pins9_data.tcl $d/ 2>/dev/null; cp -r $src/rc/. $d/rc/
ln -s $src/db/place.odb $d/db/place.odb; ln -s $src/db/place.sdc $d/db/place.sdc
root=/tmp/ckp908/qc18bacc/r35_snap; FLOW=$root/flow/tsmc65
export QC_BUILD=$B QB9_W=$B/r26_w QB_SYN=r26_ptr QB34_COLL=1 QB34_COLL_D=10 QB34_CKFIX=1 QB44_SPLIT=$gap QC_PNR_THREADS=8
export QC_PNR_SET="PRE_CTS_TCL $R/icgsplit44.tcl" QC_PNR_FROM=cts QC_PNR_TO=cts
. "$root/flow/tsmc65/common/tool.sh"; cd "$d" || exit 1
QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=/tmp/ckp908/tools/env/bin/python3 QC_PNR_OUT=$d QC_FLOW=$FLOW
/usr/bin/time -v -o openroad.log.time /tmp/ckp908/tools/env/bin/openroad -no_init -no_splash -exit -log openroad.log $FLOW/pnr/or/flow.tcl > openroad.out 2>&1 < /dev/null
echo ARM44_CTS_DONE $arm rc $? $(date +%T)
unset QC_PNR_FROM QC_PNR_TO
/tmp/ckp908/tools/env/bin/openroad -no_init -no_splash -exit -log lat.log $R/lat44.tcl > lat.out 2>&1 < /dev/null
/tmp/ckp908/tools/env/bin/openroad -no_init -no_splash -exit -log leaf.log $R/leaf44.tcl > leaf.out 2>&1 < /dev/null
echo ARM44_DONE $arm $(date +%T)
