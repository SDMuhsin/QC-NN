#!/usr/bin/env bash
# PrimeTime PX of a qcacc gate-level run (nn/gls/power.sh with qcacc/gls/env.sh; + qcacc/gls/pt_blocks.tcl):
#   qcacc/gls/power_qc.sh -d qc|gemmx [-H host] [-p period_ns] <tag> <zd|sdf>
#   Net capacitance: synthesis WLM (WireAreaLowkCon enclosed); NN_PT_ZWLM=1 for the old zero-wire numbers.
set -euo pipefail
Q=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
D=qc; H=tau1; P=()
while getopts "d:H:p:" o; do case $o in d) D=$OPTARG;; H) H=$OPTARG;; p) P=(-p "$OPTARG");; *) sed -n 2,4p "$0"; exit 2;; esac; done
shift $((OPTIND - 1))
source "$Q/env.sh"
TAG=$1; MODE=$2
[ ${#P[@]} = 0 ] && P=(-p "$(echo "$TAG" | sed -n 's/.*_\([0-9]*\)ps\(_c[0-9]*\)\{0,1\}$/\1/p' | awk '{print $1 / 1000}')")
exec "$QCNN/nn/gls/power.sh" -H "$H" "${P[@]}" "$TAG" "$MODE"
