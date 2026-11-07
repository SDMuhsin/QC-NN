#!/usr/bin/env bash
# PrimeTime PX power of a gate-level ResNet-8 layer run (nn/gls/run_gls.sh) from its SAIF, on the GLS host.
#   nn/gls/power.sh [-H host] [-p period_ns] <gls tag> <mode>
# The SAIF and the reports stay on the host (they name kit cells); only the summary <tag>_<period>.txt is
# copied back to build/nn_gls/<tag>/.  -p defaults to the clock of the GLS run (from the tag, <..>_<ps>ps).
# NN_PT_ZWLM=1: zero wire-load net capacitance (pre-erratum setting, see pt_power.tcl).
# Hooks: NN_PT_HOOK (Tcl sourced by pt_power.tcl after the summary), NN_GLS_OUT (local result root, default build/nn_gls).
set -euo pipefail
NN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QCNN=$(cd "$NN/.." && pwd)
HOST=tau1; P=""
while getopts "H:p:" o; do case $o in H) HOST=$OPTARG;; p) P=$OPTARG;; *) sed -n 2,6p "$0"; exit 2;; esac; done
shift $((OPTIND - 1))
TAG=$1; MODE=$2
P=${P:-$(echo "$TAG" | sed -n 's/.*_\([0-9]*\)ps$/\1/p' | awk '{print $1 / 1000}')}
R=${KUL_GLS_DIR:-/tmp/ckp908/qcnn_nngls}
SYN=${KUL_GLS_SYN:-/tmp/ckp908/qcnn_kulsyn/build/syn/kul_w4.2p}
SYNTREE=${KUL_GLS_FLOW:-/tmp/ckp908/qcnn_kulsyn/tree/flow/tsmc65}
RD=$R/$MODE/nn_$TAG
GX=tb_chimera_soc/fix/dut/i_cluster_domain/i_chimera_cluster_kulcluster/i_test_cluster
PFX=${P}ns
OUT=$RD/pt_$PFX
scp -q "$NN/gls/pt_power.tcl" ${NN_PT_HOOK:-} "$HOST:$RD/"
HK=${NN_PT_HOOK:+setenv NN_PT_HOOK $RD/$(basename "${NN_PT_HOOK:-x}");}
HK="$HK ${NN_PT_ZWLM:+setenv NN_PT_ZWLM $NN_PT_ZWLM;}"
DBTT=$(ssh "$HOST" ". $SYN/run.env; echo \$QC_EXTRA_DB_TT")
SDC=$(dirname "$(dirname "$SYNTREE")")/impl/kulcluster/constraints.sdc
ssh "$HOST" "cd $RD && tcsh -f -c 'source $SYNTREE/site/site.csh; setenv QC_FLOW $SYNTREE; setenv SYN $SYN; \
  setenv QC_PERIOD $P; setenv QC_SDC $SDC; setenv QC_EXTRA_DB_TT \"$DBTT\"; \
  setenv SAIF $RD/layer.saif; setenv SAIF_STRIP $GX; setenv OUT $OUT; $HK pt_shell -f pt_power.tcl >& pt_$PFX.log'; \
  grep '^Error' pt_$PFX.log | sort | uniq -c | head; cat $OUT.txt"
scp -q "$HOST:$OUT.txt" "${NN_GLS_OUT:-$QCNN/build/nn_gls}/$TAG/power_$PFX.txt"
[ -n "${NN_PT_HOOK:-}" ] && scp -q "$HOST:${OUT}_hook.txt" "${NN_GLS_OUT:-$QCNN/build/nn_gls}/$TAG/power_${PFX}_hook.txt" || true
