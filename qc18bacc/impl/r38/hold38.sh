#!/usr/bin/env bash
# R38: minimum hold (+ hub setup) fix of a re-routed copy with impl/r35/hold35.tcl in FULL re-route mode (QB35_HDR_FULL 1,
# never the incremental mode, results/r38.md F4).  Hub: R37's setup pre-hook (hubpre37: ss-derived port tightening) too.  Env as R37's act / hub ECOs (results/r37.md) minus hooks already applied.
#   hold38.sh act <tag> [margin]    hold38.sh hub <tag> [margin]      (old cells FIRM, fillers before DR)
set -u
here=$(cd "$(dirname "$0")" && pwd); S=$(cd "$here/../../.." && pwd); I=$S/qc18bacc/impl
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
blk=${1:?act|hub}; tag=${2:?tag}; HM=${3:-0.05}; d=$B/pnr/$tag; cd "$S" || exit 1
[ -e "$d/db/route_dr.odb" ] || touch "$d/db/route_dr.odb"     # hold35 copies route_dr -> route_dr_prehold before its save
export QB35_HDB=finish QB35_PER=6.5 QB35_HOLD_M=$HM QB35_HDR_FULL=1 QB35_FILL_BEFORE=1 QB37_FIRM=1 QB37_FORCE_SAVE=1 \
       QB35_THREADS=${QB35_THREADS:-14} QB37_HPRE_TCL= QB37_HPOST_TCL=${QB38_HPOST-}
case $blk in
act) export QB35_IO_TCL=$I/r35/act_io.tcl QB35_IOL=${QB38_IOL:-0.990} QB7_AOUT=0.25 QB7_DIN=0.74 QB15_GADJ_L="M2-M3 0.6" ;;
hub) export QB35_IO_TCL=$I/r37/hubio37.tcl QB37_HUBIO=$B/r26_w/cfg_$tag/hub_io.tcl QB35_IOL=${QB38_IOL:-1.604} \
            QB37_FR="actout 0.26" QB37_OMIN=1 QB37_DONTTOUCH="u_top_U92356" QB15_GADJ_L="M5-M9 0.10 M2-M3 0.6" \
            QB37_HPRE_TCL=$I/r37/hubpre37.tcl QB37_ICGCLONE= QB37_SSX=${QB38_SSX-$B/pnr/r35_hubC/r37_ssx_ports.txt} QB37_SPCT=5 QB37_SM=${QB38_SM:-0.0} ;;
esac
bash "$I/r35/run35.sh" hold "$tag"
rm -f "$d/db/route_dr_prehold.odb"
