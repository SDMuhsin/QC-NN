#!/usr/bin/env bash
# R33: production place step (r31_B env: impl/r31 run31 -> r28 -> r22 gate) on <tag> from its db/pdn.odb, PRE_PLACE_TCL = $1
root=/tmp/ckp908/qc18bacc/r31_snap4; B=/tmp/ckp908/qc18bacc/build; R21=$root/qc18bacc/impl/r21; tag=$2
export QC_BUILD=$B QB_SB=649 QB21_MAXFO=32 QB22_FP=pn QB22_S2S=1 QB15_FP=mid QB_SYN=r26_ptr QB9_W=$B/r26_w QB10_SRD=0
export QB9_PER=2.80 QB_PT_PERIOD=2.80 QB_TD=1 QB_RD=0 QB_DPL_ARGS="-max_displacement 500" QB9_CHBLK=40 QB9_GPL2=${QB9_GPL2:-1} QB9_GPL2_DENS=0.65
export QB_GPL_INCR_DENS=0.65 QB_IO_LAT=1.30 QB_RT_LOOPS=0 QB_TNS=10 QB9_GR_ITER=10 QB15_GADJ_L="M5-M9 0.10 M2-M3 0.6" QB31_SDC=1 QC_PNR_THREADS=16
export QB_PC_HOOK=$root/qc18bacc/impl/r24/pc24.tcl QB24_MODE=fix
SET="QB_GPL_INCR_DENS 0.65 PRE_PLACE_TCL $1 PRE_ROUTE_TCL $R21/route_pre.tcl POST_GRT_TCL $R21/post_grt.tcl"
QC_PNR_SET="$SET" QC_PNR_FROM=place QC_PNR_TO=place $root/flow/tsmc65/pnr/run_pnr.sh $root/qc18bacc/impl/r10b/hub.cfg $tag
