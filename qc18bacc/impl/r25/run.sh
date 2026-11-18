#!/usr/bin/env bash
# R25 (results/r25.md): measurement only on r24_d65t (no flow default changed).  On tau from the snapshot root:
#   qc18bacc/impl/r25/run.sh dr <src> <tag>   short DR of <src>/db/grt.odb in a new run <tag> (grt.odb / grt.sdc /
#                                             route.guide symlinked): dr25.tcl = impl/r8/dr.tcl stopped after
#                                             detailed_route; QB_DR_ITER [3], QB_DR_ARGS [-drc_report_iter_step 1];
#                                             env as impl/r21/run.sh dr (no antenna, no fillers, 16 threads)
#   qc18bacc/impl/r25/run.sh dump <tag>       50 um bin dump of db/[QB_DB grt].odb (dump25.tcl) -> <tag>/r25/
#   qc18bacc/impl/r25/run.sh an <tag> <rpt>   marker bins / correlations (an25.py) of <rpt> with <tag>/r25/
#   qc18bacc/impl/r25/run.sh cls <tag>        cls25.tcl = impl/r24/cls24.tcl + all reg2reg groups, worst-path depth,
#                                             endpoint slack histogram (db/cts_rt.odb, QB_IO_LAT [1.30], 2.30 ns)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad; PY=$TOOLS/env/bin/python3
export QB9_W=${QB9_W:-$B/r10b_ww} QB_IO_LAT=${QB_IO_LAT:-1.30}
kit() { . "$root/flow/tsmc65/common/tool.sh"
        QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_FLOW=$FLOW QC_PY=$PY; }
step=${1:?step}
case $step in
dr)  src=$B/pnr/${2:?src}; tag=${3:?tag}; d=$B/pnr/$tag; mkdir -p "$d/db" "$d/rpt"
     for f in config.tcl kit.env macros.txt; do cp "$src/$f" "$d/"; done; cp -r "$src/rc" "$d/"
     for f in db/grt.odb db/grt.sdc route.guide; do ln -sf "$src/$f" "$d/$f"; done
     mkdir -p "$QB9_W/cfg_$tag"; cp "$QB9_W/cfg_${2}/"* "$QB9_W/cfg_$tag/"
     ( kit; cd "$d" && QC_PNR_OUT=$d QB_ANT_CHECK=0 QB8_DR_FILL=0 QB8_DR_THREADS=${THR:-16} QB_DR_ITER=${QB_DR_ITER:-3} \
         QB_DR_ARGS="${QB_DR_ARGS:--drc_report_iter_step 1}" /usr/bin/time -v -o dr.log.time "$OR" -no_init -no_splash -exit \
         -log dr.log "$here/dr25.tcl" > dr.out 2>&1 < /dev/null )
     grep -h "Number of violations\|r25 dr" "$d/dr.log" | tail -4; ls -la "$d/rpt" ;;
dump) d=$B/pnr/${2:?tag}; mkdir -p "$d/r25"
     ( kit; cd "$d" && QC_PNR_OUT=$d QB25_OUT=$d/r25 "$OR" -no_init -no_splash -exit "$here/dump25.tcl" > r25/dump.log 2>&1 < /dev/null )
     grep -h "R25" "$d/r25/dump.log" | tail -3 ;;
an)  d=$B/pnr/${2:?tag}; "$PY" -I "$here/an25.py" "$d/r25" "${3:?rpt}" ;;
cls) d=$B/pnr/${2:?tag}
     ( kit; cd "$d" && QB21_PROP=1 QB_DB=${QB_DB:-cts_rt} QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit "$here/cls25.tcl" \
         > r25_cls.log 2>&1 < /dev/null )
     grep -h "R21_CLS reg2reg\|R25_\|^Error" "$d/r25_cls.log" | head -60 | cut -c1-240 ;;
*)   sed -n '2,10p' "$0"; exit 1 ;;
esac
