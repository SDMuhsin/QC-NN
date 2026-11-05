#!/usr/bin/env bash
# Synthesis / timing of chimera's Snitch cluster (qc_snitch_cluster_top) on TSMC 65 nm, run on the server from the
# repo root of a tree that has the sources (impl/snitch_cluster/sync_src.sh) and the macro views
# (flow/tsmc65/sram/mc_gen.sh gen hw/tech/tsmc65/macros.txt, same host: the views are host-local).
# QC_VARIANT=fp (default; top snitch_cluster_wrapper of sim/cfg/chimera_fp.hjson, tags fp_*) or chimera (chimera-exact
# integer-only cluster, top qc_snitch_cluster_top, tags snc_*).
#   impl/snitch_cluster/run.sh elab [period]          elaboration / link check only (tag <pfx>_elab)
#   impl/snitch_cluster/run.sh syn  [period] [tag]    DC (QC_TOPO=1: topographical), default 2.0 ns at ss
#   impl/snitch_cluster/run.sh pt   <tag> [corner..]  PrimeTime ss / tt / ff (per-clock fmax, power)
#   impl/snitch_cluster/run.sh summary <tag>          results/<tag>/*.txt (area by hierarchy, timing, fmax, power)
#   impl/snitch_cluster/run.sh all  [period] [tag]    syn + pt + summary
# Builds go to QC_BUILD (default /tmp/$USER/qcnn/build, host-local: the NFS home has no room).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FLOW=$ROOT/flow/tsmc65
. "$FLOW/site/sram.sh"
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qcnn/build}
export QC_SDC=$HERE/constraints.sdc QC_HOOK=$HERE/dc_hook.tcl QC_PT_HOOK=$HERE/pt_hook.tcl QC_CLK=clu_clk
export QC_CORES=${QC_CORES:-8}
# variant (QC_VARIANT): fp = sim/cfg/chimera_fp.hjson cluster (primary), chimera = chimera-exact integer cluster
case "${QC_VARIANT:-fp}" in
fp)      TOP=snitch_cluster_wrapper; FL=$HERE/fp.f;      PFX=fp ;;
chimera) TOP=qc_snitch_cluster_top;  FL=$HERE/chimera.f; PFX=snc ;;
*)       echo "unknown QC_VARIANT ${QC_VARIANT} (fp | chimera)"; exit 1 ;;
esac

# macro .db per flow corner: ss / tt / ff = the first three characterisation corners of sram.sh (ss, tt, ff cold)
IFS=, read -r C_SS C_TT C_FF _ <<< "$QC_MC_CORNERS"
dbs() { sed 's/#.*//' "$ROOT/hw/tech/tsmc65/macros.txt" | awk 'NF >= 5 { print $1 }' |
        while read -r i; do printf '%s ' "$QC_MC_OUT/$i/${i}_$1_syn.db"; done; }
export QC_EXTRA_DB_SS="$(dbs "$C_SS")" QC_EXTRA_DB_TT="$(dbs "$C_TT")" QC_EXTRA_DB_FF="$(dbs "$C_FF")"
for f in $QC_EXTRA_DB_SS $QC_EXTRA_DB_TT $QC_EXTRA_DB_FF; do
    [ -f "$f" ] || { echo "missing macro view $f (flow/tsmc65/sram/mc_gen.sh gen hw/tech/tsmc65/macros.txt)"; exit 1; }
done

syn() { "$FLOW/syn/run_dc.sh" "$FL" "$TOP" "$1" "$2"; }
pt()  { local t=$1; shift; "$FLOW/sta/run_pt.sh" "$t" "$@"; }
summary() { "$HERE/summarize.sh" "$QC_BUILD/syn/$1" "$HERE/results/$1"; }

cmd=${1:-}; shift || true
case "$cmd" in
elab)    QC_ELAB_ONLY=1 syn "${1:-2.0}" ${PFX}_elab ;;
syn)     p=${1:-2.0}; syn "$p" "${2:-${PFX}_p${p}$([ "${QC_TOPO:-0}" = 1 ] && echo _topo)}" ;;
pt)      pt "$@" ;;
summary) summary "$1" ;;
all)     p=${1:-2.0}; t=${2:-${PFX}_p${p}$([ "${QC_TOPO:-0}" = 1 ] && echo _topo)}
         syn "$p" "$t" && pt "$t" && summary "$t" ;;
*)       sed -n '2,13p' "$0"; exit 1 ;;
esac
echo "SNC_DONE $cmd $*"
