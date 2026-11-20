#!/usr/bin/env bash
# R32: pp32.tcl on run <tag> corner <c> (env as impl/r31/pt31.sh)
root=/tmp/ckp908/qc18bacc/r31_snap4; B=/tmp/ckp908/qc18bacc/build; tag=${1:?tag}; c=${2:?corner}; d=$B/pnr/$tag
export QB_SYN=r26_ptr QB9_W=$B/r26_w QB_IO_LAT=${QB_IO_LAT:-1.30}
( . $root/flow/tsmc65/common/tool.sh; . $d/kit.env; set -a; . $B/syn/$QB_SYN/run.env; set +a
  mkdir -p /tmp/ckp908/qc18bacc/r33/w33_${tag}_$c; cd /tmp/ckp908/qc18bacc/r33/w33_${tag}_$c || exit 1
  QC_PNR_OUT=$d QC_TOP=$TOP QC_CORNER=$c QB21_SDC=$QB9_W/cfg_$tag/qb_hub.sdc QB_PT_PERIOD=${QB_PT_PERIOD:?} \
  R31_PTHUB=$root/qc18bacc/impl/r21/pt_hub.tcl qc_tool /tmp/ckp908/qc18bacc/r33/pp33c_${tag}_$c.log pt_shell -f /tmp/ckp908/qc18bacc/r33/pp33c.tcl )
rm -rf /tmp/ckp908/qc18bacc/r33/w33_${tag}_$c
grep -h "^R33" /tmp/ckp908/qc18bacc/r33/pp33c_${tag}_$c.log
