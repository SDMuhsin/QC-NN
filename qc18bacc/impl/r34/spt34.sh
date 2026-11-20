#!/usr/bin/env bash
# R34 SPEF test on tau6 run r33_fx: def2spef OR copy without / with QC_SPEF_ORFIX, then read_spef in OpenROAD
root=/tmp/ckp908/qc18bacc/r34_snap6; B=/tmp/ckp908/qc18bacc/build; d=$B/pnr/${1:-r33_fx}; W=/tmp/ckp908/qc18bacc/r34
. $root/flow/tsmc65/common/tool.sh
export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
export QC_BUILD=$B QC_PNR_OUT=$d QB_IO_LAT=${QB_IO_LAT:-1.39} QB9_W=$B/r26_w QB_SYN=r26_ptr
cd $W
for v in ${R34_V:-0 1}; do
  ( QC_SPEF_ORFIX=$v python3 -I $root/flow/tsmc65/pnr/py/def2spef.py $d/out/qb_hub.def $d/out/qb_hub.conn $d/rc/tt.txt $W/or_$v.spef > $W/d2s_$v.log 2>&1
    R34_SPEF=$W/or_$v.spef R34_RPT=$W/spt_$v.rpt /tmp/ckp908/tools/env/bin/openroad -no_init -no_splash -exit $W/spt34.tcl > $W/spt_$v.log 2>&1 < /dev/null
    rm -f $W/or_$v.spef; echo SPT_DONE $v ) &
done; wait
