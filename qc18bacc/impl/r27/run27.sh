#!/usr/bin/env bash
# R27 (results/r27.md): repair_design attribution + max-transition sweep of the hub (r26_p1 settings), place step only.
# On tau from the snapshot root:
#   qc18bacc/impl/r27/run27.sh mk <tag>       impl/r24/run24.sh mk <tag> <r26_p1> with QB24_LINK pdn
#   qc18bacc/impl/r27/run27.sh pl <tag>       place step only (QC_PNR_FROM/TO place) with the r22/r24/r26 env and SET,
#                                             PRE_PLACE_TCL = impl/r27/pre27.tcl (QB27_MODE save|replay, QB27_LOCS,
#                                             QB_MAXTRAN, QB27_BUFMIN)
#   qc18bacc/impl/r27/run27.sh cls <tag>      impl/r24/cls24.tcl on db/place.odb, ideal clocks (pre-CTS), QB_IO_LAT 1.30
#   qc18bacc/impl/r27/run27.sh st <tag>       stats27.tcl: std area / instances / signal pins / buffers of db/place.odb
#   qc18bacc/impl/r27/run27.sh attr <run>     attr27.tcl: pdn -> place repair attribution of <run> (dump on tau, agg27.py)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd); I=$root/qc18bacc/impl
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
export QB_SYN=${QB_SYN:-r26_ptr} QB9_W=${QB9_W:-$B/r26_w}
export QB_SB=649 QB21_MAXFO=32 QB10_SRD=0 QB9_PER=2.30 QB_TD=1 QB_RD=0 QB_DPL_ARGS="-max_displacement 500" QB9_CHBLK=40 \
       QB9_GPL2=1 QB9_GPL2_DENS=0.65 QB_IO_LAT=1.30 QB_RT_LOOPS=0 QB_TNS=10 QC_PNR_THREADS=${QC_PNR_THREADS:-16}
R21=$I/r21
SET="QB_GPL_INCR_DENS 0.65 PRE_PLACE_TCL $here/pre27.tcl PRE_ROUTE_TCL $R21/route_pre.tcl POST_GRT_TCL $R21/post_grt.tcl"
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad
kit() { . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_FLOW=$FLOW QC_PY=$TOOLS/env/bin/python3; }
step=${1:?step}; tag=${2:?tag}; d=$B/pnr/$tag
case $step in
mk)   QB24_LINK=pdn "$I/r24/run24.sh" mk "$tag" "$B/pnr/${QB27_SRC:-r26_p1}" ;;
pl)   QC_PNR_SET="$SET" QC_PNR_FROM=place QC_PNR_TO=place "$root/flow/tsmc65/pnr/run_pnr.sh" "$I/r10b/hub.cfg" "$tag"
      grep -h "R27\|drv violations\|repair_design on\|RSZ-0038\|RSZ-0039\|QC_PNR place\|step place done\|ERROR" "$d/openroad.log" | cut -c1-200 ;;
cls)  ( kit; cd "$d" && QB_DB=place QB21_PROP=0 QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit "$I/r24/cls24.tcl" > r27_cls.log 2>&1 < /dev/null )
      grep -h "R21_CLS [ir]\|^Error" "$d/r27_cls.log" | head -8 ;;
st)   ( kit; cd "$d" && QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit "$here/stats27.tcl" > r27_st.log 2>&1 < /dev/null )
      grep -h "R27_ST\|^Error" "$d/r27_st.log" ;;
attr) ( kit; cd "$d" && QC_PNR_OUT=$d QB27_OUT=${QB27_OUT:-$B/r27_attr_$tag} "$OR" -no_init -no_splash -exit "$here/attr27.tcl" > r27_attr.log 2>&1 < /dev/null )
      grep -h "R27_\|^Error" "$d/r27_attr.log" | head -20 ;;
*)    sed -n '2,10p' "$0"; exit 1 ;;
esac
