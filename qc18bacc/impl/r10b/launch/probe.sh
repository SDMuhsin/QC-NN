#!/bin/bash
# usage: probe.sh <rundir> <tclfile> <outfile> [env assignments]
d=$1; t=$2; o=$3; shift 3
root=/tmp/ckp908/qc18bacc/r10b_snap; cd $root
. flow/tsmc65/common/tool.sh
export QC_BUILD=/tmp/ckp908/qc18bacc/build
QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=/tmp/ckp908/tools/env/bin/python3
cd $d && env QC_PNR_OUT=$d "$@" /usr/bin/time -v -o $o.time /tmp/ckp908/tools/env/bin/openroad -no_init -no_splash -exit $t > $o 2>&1 < /dev/null
