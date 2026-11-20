#!/usr/bin/env bash
# R33 OpenROAD runner: or33.sh <run tag> <script> <log>   (env passed through)
root=/tmp/ckp908/qc18bacc/r31_snap4; B=/tmp/ckp908/qc18bacc/build; d=$B/pnr/$1
. $root/flow/tsmc65/common/tool.sh
export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
export QC_PY=${QC_PY:-python3} QC_BUILD=$B QC_PNR_OUT=$d
cd /tmp/ckp908/qc18bacc/r33 && /usr/bin/time -v -o $3.time /tmp/ckp908/tools/env/bin/openroad -no_init -no_splash -exit $2 > $3 2>&1 < /dev/null
