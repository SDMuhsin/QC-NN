#!/usr/bin/env bash
# R18 (results/r18.md): measurement only on the R16 route input r16_se (db/cts_rt.odb: CTS + post-CTS repair done).
#   qc18bacc/impl/r18/run.sh grt <adj> <tag>   GRT probe (impl/r10b/grt_probe.tcl: M2-M7, QB_GI 10 iterations, -allow_congestion,
#                                              congestion report + guides) at layer adjustment <adj> in $QC_BUILD/pnr/<tag>
#   qc18bacc/impl/r18/run.sh dump <tag>        net classes + cell classes / rows (impl/r18/dump.tcl), OBS / PDN (impl/r12/q3dump.tcl)
# Analysis (python, numpy): impl/r18/cuts.py (cut decomposition), impl/r18/geo.py (placement), impl/r18/ovfmap.py (maps).
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; SRC=${QB18_SRC:-r16_se}
step=${1:?step}
mk() { d=$B/pnr/$1; mkdir -p "$d/db" "$d/rpt"; cp "$B/pnr/$SRC/config.tcl" "$B/pnr/$SRC/kit.env" "$d/"; rm -rf "$d/rc"; cp -r "$B/pnr/$SRC/rc" "$d/"
     ln -sf "$B/pnr/$SRC/db/cts_rt.odb" "$d/db/cts_rt.odb"; ln -sf "$B/pnr/$SRC/db/cts.sdc" "$d/db/cts_rt.sdc"; }
orun() { ( . "$root/../flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
         cd "$1" && QC_FLOW=$FLOW QC_PNR_OUT=$1 /usr/bin/time -v -o "$2.time" "$TOOLS/env/bin/openroad" -no_init -no_splash -exit -log "$2.log" "$3" > "$2.out" 2>&1 < /dev/null ) ; }
case $step in
grt) adj=${2:?adj}; tag=${3:?tag}; mk "$tag"
     QB_DB=cts_rt QB_GADJ=$adj QB_GI=${QB_GI:-10} QB_GREP=1 QB_GGUIDE=1 QC_PNR_THREADS=${QC_PNR_THREADS:-8} \
       orun "$B/pnr/$tag" grt "$root/impl/r10b/grt_probe.tcl"; echo "R18_GRT_DONE $tag rc $?" ;;
dump) tag=${2:?tag}; mk "$tag"
     QB_DB=cts_rt QB18_OUT=$B/pnr/$tag/rpt orun "$B/pnr/$tag" dump "$here/dump.tcl"
     QB_DB=cts_rt QB12_OUT=$B/pnr/$tag/rpt/obs.txt orun "$B/pnr/$tag" obs "$root/impl/r12/q3dump.tcl"; echo "R18_DUMP_DONE $tag" ;;
*) sed -n '2,8p' "$0"; exit 1 ;;
esac
