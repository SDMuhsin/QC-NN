#!/usr/bin/env bash
# R21 pre-route wire budget of a hub run (results/r21.md), on tau from the snapshot root:
#   qc18bacc/impl/r21/budget.sh <run> <gtag> <odb> <outdir> [run_adj_spec]
#   (gtag p = the P&R run's own GRT: impl/r10b/run.sh ana <run> p first, for the cone classes)
#   1. impl/r12/q3dump.tcl (layers / OBS / PDN) and impl/r12/q1dump.tcl (placement) of db/<odb>.odb, q1dump of db/init.odb
#   2. impl/r21/cuts21.py on <run>/grt_<gtag>/route.guide (or <run>/route.guide when gtag = p) + netcls2 of that GRT
#   3. impl/r12/q1.py repair attribution (init vs <odb>) by source class
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
B=${QC_BUILD:-/tmp/$USER/qc18bacc/build}; TOOLS=${QC_TOOLS:-/tmp/$USER/tools}
run=$B/pnr/${1:?run}; g=${2:?gtag}; db=${3:?odb}; o=${4:?outdir}; spec=${5:-"M2-M4 0.25 M5-M9 0.10"}
mkdir -p "$o"
if [ "$g" = p ]; then gd=$run/grt_p; gl=$run/openroad.log; else gd=$run/grt_$g; gl=$gd/grt.log; fi
[ -s "$gd/netcls2.txt" ] || QB9_W=${QB9_W:-$B/r10b_ww} "$root/qc18bacc/impl/r10b/run.sh" ana "${1}" "$g" > "$o/ana.log" 2>&1
orun() { ( . "$root/flow/tsmc65/common/tool.sh"; export QC_KIT=$(tcsh -f -c "source $FLOW/site/site.csh >& /dev/null; printenv QC_KIT")
         cd "$run" && QC_FLOW=$FLOW QC_PNR_OUT=$run QB_DB=$1 QB12_OUT=$2 "$TOOLS/env/bin/openroad" -no_init -no_splash -exit "$3" > "$2.log" 2>&1 < /dev/null ) ; }
[ -s "$o/obs.txt" ] || orun "$db" "$o/obs.txt" "$root/qc18bacc/impl/r12/q3dump.tcl"
[ -s "$o/dump_db.txt" ] || orun "$db" "$o/dump_db.txt" "$root/qc18bacc/impl/r12/q1dump.tcl"
[ -s "$o/dump_init.txt" ] || orun init "$o/dump_init.txt" "$root/qc18bacc/impl/r12/q1dump.tcl"
echo R21B_DUMPS $(date +%T)
python3 -I "$here/cuts21.py" "$gd/route.guide" "$gd/netcls2.txt" "$o/obs.txt" "$gl" "$run/mplace.tcl" "$o" "$spec" ${QB21_ADJ:-0.25} > "$o/cuts21.log" 2>&1
echo R21B_CUTS rc $? $(date +%T)
python3 -I "$root/qc18bacc/impl/r12/q1.py" "$o/dump_init.txt" "$o/dump_db.txt" "$run/rpt/dumpdb.txt" "$gd/netcls2.txt" "$root/qc18bacc/impl/r10b/ovf10.py" "$o" > "$o/q1.log" 2>&1
echo R21B_Q1 rc $? $(date +%T)
