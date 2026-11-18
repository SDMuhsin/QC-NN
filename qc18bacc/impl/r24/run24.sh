#!/usr/bin/env bash
# R24 (results/r24.md): post-CTS legalisation diagnosis / fix on copies of a hub run (on tau, from the snapshot root):
#   qc18bacc/impl/r24/run24.sh mk <tag> <src run dir>   $QC_BUILD/pnr/<tag>: small files copied, db/{place,cts}.odb|sdc
#                                                       symlinked (QB24_LINK: "pdn" for a re-place run), IO budget
#                                                       dir cfg_<src> -> cfg_<tag>
#   qc18bacc/impl/r24/run24.sh pl <tag>                 impl/r22/run.sh prod from place (QB22_FROM place, QB24_DENS for
#                                                       QB_GPL_INCR_DENS + QB9_GPL2_DENS) with QB_PC_HOOK pc24 (QB24_MODE fix)
#   qc18bacc/impl/r24/run24.sh or <tag>                 pc24_main.tcl (QB24_MODE meas | hmeas | fix, QB24_DB, QB24_FIX ...)
#   qc18bacc/impl/r24/run24.sh clk <tag>                clk24.tcl clock-tree census of db/[QB_DB cts].odb
#   qc18bacc/impl/r24/run24.sh cls <tag>                cls24.tcl (r21 sta_cls + reg2reg groups) on db/[QB_DB cts_rt].odb
#   qc18bacc/impl/r24/run24.sh disp <tag> [a b]         disp24.py on r24/d_<a>.txt -> d_<b>.txt (default hu hl)
# Env defaults = impl/r22/run.sh (QB_IO_LAT 1.30, QB_DPL_ARGS "-max_displacement 500", QB_RT_LOOPS 1).
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
export QB9_W=${QB9_W:-$B/r10b_ww} QB_IO_LAT=${QB_IO_LAT:-1.30} QB_RT_LOOPS=${QB_RT_LOOPS:-1}
export QB_DPL_ARGS=${QB_DPL_ARGS:-"-max_displacement 500"} QC_PNR_THREADS=${QC_PNR_THREADS:-16}
export QB_PC_HOOK=${QB_PC_HOOK:-$here/pc24.tcl}
step=${1:?step}; tag=${2:?tag}; d=$B/pnr/$tag
case $step in
mk)  s=${3:?src}; mkdir -p "$d/db" "$d/rpt"
     for f in config.tcl mplace.tcl pins9_data.tcl macros.txt kit.env; do [ -f "$s/$f" ] && cp "$s/$f" "$d/"; done
     for f in ${QB24_LINK:-place cts}; do ln -sf "$s/db/$f.odb" "$d/db/$f.odb"; ln -sf "$s/db/$f.sdc" "$d/db/$f.sdc"; done
     cp -r "$QB9_W/cfg_$(basename "$s")" "$QB9_W/cfg_$tag"; echo R24_MK $d ;;
or)  ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$d" && QC_FLOW=$FLOW QC_PNR_OUT=$d QC_PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3 /usr/bin/time -v -o r24_or.time "${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad" \
         -no_init -no_splash -exit -log r24_or.log "$here/pc24_main.tcl" > r24_or.out 2>&1 < /dev/null )
     grep -h "QC_PNR post\|QC_PNR r24\|ERROR" "$d/r24_or.log" | cut -c1-170; echo R24_OR_DONE $tag ;;
pl)  QB22_FROM=place QB22_SET_X="QB_GPL_INCR_DENS ${QB24_DENS:-0.80}" QB9_GPL2_DENS=${QB24_DENS:-0.80} QB24_MODE=${QB24_MODE:-fix} \
       "$here/../r22/run.sh" prod "$tag" ;;
clk) ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$d" && QC_FLOW=$FLOW QC_PNR_OUT=$d QC_PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3 "${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad" \
         -no_init -no_splash -exit "$here/clk24.tcl" > r24_clk.log 2>&1 < /dev/null ); grep -h "R24_CLK\|^Error" "$d/r24_clk.log" | cut -c1-160 ;;
cls) ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
       cd "$d" && QB21_PROP=1 QB_DB=${QB_DB:-cts_rt} QC_FLOW=$FLOW QC_PNR_OUT=$d QC_PY=${QC_TOOLS:-/tmp/$USER/tools}/env/bin/python3 \
         "${QC_TOOLS:-/tmp/$USER/tools}/env/bin/openroad" -no_init -no_splash -exit "$here/cls24.tcl" > r24_cls_${QB_DB:-cts_rt}.log 2>&1 < /dev/null )
     grep -h "R21_CLS\|R24_GRP\|^Error" "$d/r24_cls_${QB_DB:-cts_rt}.log" | cut -c1-200 ;;
disp) python3 -I "$here/disp24.py" "$d/r24" "${3:-hu}" "${4:-hl}" ;;
*)   sed -n '2,7p' "$0"; exit 1 ;;
esac
