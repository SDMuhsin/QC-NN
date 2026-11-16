#!/usr/bin/env bash
# R10b south hub hard block (results/r10b.md), on tau from the repository root, QC_BUILD as R8:
#   (env QB_SYN [r10_rpc] netlist, QB9_W [$B/r10b_w] partition work dir)
#   qc18bacc/impl/r10b/run.sh dump|part|ports|sdc|equiv   = impl/r9b/run.sh steps on QB_SYN / QB9_W (partition + check)
#   qc18bacc/impl/r10b/run.sh fp  <tag>      init, macro dump, mplace10.py (QB_SB / QB_CH / QB_PGAP / QB_P8SLOT), sdc.py,
#                                            pins9.py data, floorplan + pdn (pins10.tcl: s_q fixed j-major)
#   qc18bacc/impl/r10b/run.sh pnr <tag>      place .. global route (hub.cfg knobs + QB10_SRD / QB10_SDENS, QB9_GR_ITER)
#   qc18bacc/impl/r10b/run.sh grt <tag> <db> GRT-only rerun from checkpoint <db> (grt.tcl): QB_GI iterations, overflow
#                                            report, guides, netcls dump -> <run>/grt_<QB_GTAG>/
#   qc18bacc/impl/r10b/run.sh ana <tag> <g>  overflow by region / class / family (ovf10.py) + guide demand of grt_<g> (p = pnr GRT)
#   qc18bacc/impl/r10b/run.sh dr  <tag>      detailed route in a fresh process (impl/r8/run.sh dr)
# tau wrappers used for the R10b runs (env per run): impl/r10b/launch/ (r10b_launch.sh fp+pnr, r10b_pnr.sh, *_part.sh)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; B=$QC_BUILD
TOOLS=${QC_TOOLS:-/tmp/$USER/tools}; OR=$TOOLS/env/bin/openroad; PY=$TOOLS/env/bin/python3
export QB_SYN=${QB_SYN:-r10_rpc}
W=${QB9_W:-$B/r10b_w}; export QB9_W=$W; mkdir -p "$W"
kit() { . "$root/flow/tsmc65/common/tool.sh"
        QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT"); export QC_KIT QC_PY=$PY; }
step=${1:?step}
case $step in
dump|part|ports|sdc|equiv) exec "$root/qc18bacc/impl/r9b/run.sh" "$step" ;;
fp)  tag=${2:?tag}; d=$B/pnr/$tag; kit; mkdir -p "$W/cfg_$tag"
     "$PY" -I "$root/qc18bacc/impl/r9b/sdc.py" "$W/bnd_bits.txt" "${QB9_PER:-1.85}" "$W/cfg_$tag/qb_hub.sdc" "$W/cfg_$tag/hub_io.tcl" || exit 1
     QC_PNR_TO=init "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/hub.cfg" "$tag" || exit 1
     ( cd "$d" && QB_RUN=$d "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r5b/dump_macros.tcl" > dump.log 2>&1 < /dev/null )
     "$PY" -I "$here/mplace10.py" "$d/macros.txt" "$d/mplace.tcl" || exit 1
     x0=$(sed -n 's/^set ::QB9_X0 //p' "$d/mplace.tcl")
     "$PY" -I "$root/qc18bacc/impl/r9b/pins9.py" "$W/bnd_bits.txt" "$B/r5b_blk/qb_col_blk.lef" "$x0" "$d/pins9_data.tcl" || exit 1
     QC_PNR_FROM=floorplan QC_PNR_TO=pdn "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/hub.cfg" "$tag" ;;
pnr) tag=${2:?tag}; kit
     QB_GRT_STOP=${QB_GRT_STOP:-1} QC_PNR_FROM=${QC_PNR_FROM:-place} "$root/flow/tsmc65/pnr/run_pnr.sh" "$here/hub.cfg" "$tag" ;;
grt) tag=${2:?tag}; d=$B/pnr/$tag; kit; cd "$d" || exit 1; g=$d/grt_${QB_GTAG:-a}; mkdir -p "$g"
     QB_DB=${3:-cts} QB_GOUT=$g QC_PNR_OUT=$d /usr/bin/time -v -o "$g/grt.time" "$OR" -no_init -no_splash -exit \
         -log "$g/grt.log" "$here/grt.tcl" > "$g/grt.out" 2>&1 < /dev/null
     grep -h "^R10B" "$g/grt.out"; grep -h "Elapsed\|Maximum res" "$g/grt.time" ;;
ana) tag=${2:?tag}; gt=${3:-a}; d=$B/pnr/$tag; g=$d/grt_$gt; kit; cd "$d" || exit 1   # overflow analysis of grt_<gt>
     if [ "$gt" = p ] && [ ! -d "$g" ]; then          # p = the pnr run's own GRT (route step, db/grt.odb)
         mkdir -p "$g"; ln -s ../rpt/gr_congestion.rpt "$g/"; ln -s ../route.guide "$g/"; ln -s grt.odb db/grt_p.odb
         grep -h "r9b grt" summary.txt | sed 's/^r9b/R10B/' > "$g/grt.out"; fi
     for t in netcls dumpdb; do QB_DB=grt_$gt QC_PNR_OUT=$d "$OR" -no_init -no_splash -exit "$root/qc18bacc/impl/r9b/$t.tcl" > "$g/$t.out" 2>&1 < /dev/null & done; wait
     python3 -I "$root/qc18bacc/impl/r9b/cone.py" rpt/dumpdb.txt rpt/netcls.txt "$g/netcls2.txt" || exit 1
     H=$(sed -n 's/^set ::QB9_H //p' mplace.tcl)
     python3 -I "$here/ovf10.py" "$g/gr_congestion.rpt" "$g/netcls2.txt" "$g/grt.out" 860 3990 "$H" > "$g/ovf.txt"
     python3 -I "$root/qc18bacc/impl/r9b/guide9.py" "$g/route.guide" "$(sed -n 's/^LEF="\(.*\)"$/\1/p' kit.env)" 860 3990 "$H" >> "$g/ovf.txt"
     grep -h "^R10B grt" "$g/grt.out" >> "$g/ovf.txt"; cat "$g/ovf.txt" ;;
dr)  tag=${2:?tag}; QB8_DR_THREADS=${QB8_DR_THREADS:-12} "$root/qc18bacc/impl/r8/run.sh" dr "$tag" ;;
*) sed -n '2,12p' "$0"; exit 1 ;;
esac
echo "R10B_DONE $step"
