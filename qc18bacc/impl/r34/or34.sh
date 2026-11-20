#!/usr/bin/env bash
# R34 OpenROAD runner: or34.sh <run tag> <script> <log>   (env passed through; snapshot r34_snap2)
root=/tmp/ckp908/qc18bacc/r34_snap2; B=/tmp/ckp908/qc18bacc/build; d=$B/pnr/$1
. $root/flow/tsmc65/common/tool.sh
export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
export QC_PY=${QC_PY:-python3} QC_BUILD=$B QC_PNR_OUT=$d QB9_W=$B/r26_w QB_SYN=r26_ptr
cd /tmp/ckp908/qc18bacc/r34 && /tmp/ckp908/tools/env/bin/openroad -no_init -no_splash -exit $2 > $3 2>&1 < /dev/null
