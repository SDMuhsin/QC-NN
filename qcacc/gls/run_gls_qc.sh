#!/usr/bin/env bash
# Gate-level s2 run in chimera (nn/gls/run_gls.sh with the hooks of qcacc/gls/env.sh) up to a step, + its SAIF.
#   qcacc/gls/run_gls_qc.sh -d qc|gemmx [-m zd|sdf] [-c clk_ps] [-s conv1|add1] [-k call] [-w "t0 t1"] [-H host]
# conv1 in gemmx mode = 2 per-group calls (conv1_g0 = GeMMX call 3, conv1_g1 = call 4): stop after conv1_g1, SAIF of
# the call given with -k (one run per call, tag suffix _c<k>; Questa's power reset does not restart the SAIF).  RTL reference (same ELF): build/qcacc/rtl/<d>_stop_<step>_<clk>ps
# (qcacc/hw/sim/run_rtl_qc.sh -t .. -c .. -- -DNN_STOP_AFTER=<idx>).  Results build/qcacc/gls/<d>_<step>_<m>_<clk>ps.
set -euo pipefail
Q=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
D=qc; M=zd; C=2000; S=conv1; W=""; H=tau1; K=""
while getopts "d:m:c:s:w:H:k:" o; do
  case $o in d) D=$OPTARG;; m) M=$OPTARG;; c) C=$OPTARG;; s) S=$OPTARG;; w) W=$OPTARG;; H) H=$OPTARG;; k) K=$OPTARG;;
             *) sed -n 2,8p "$0"; exit 2;; esac
done
source "$Q/env.sh"
read -r STEP IDX CALLS < <(cd "$QCNN" && python3 -c "
import torch
from qcacc.compile.lower import QCProgram
st = [s.name for s in QCProgram(torch.load('$S2', weights_only=False), '$D', True if '$D' == 'gemmx' else None).steps]
last = max(i for i, n in enumerate(st) if n == '$S' or n.startswith('${S}_g'))
conv = [n for n in st if n.startswith('conv')]
calls = [str(k + 1) for k, n in enumerate(conv) if n == '$S' or n.startswith('${S}_g')] or ['0']
print(st[last], last, ' '.join(calls))" 2>/dev/null | tail -1)
if [ -n "$K" ]; then CALLS=$K; elif [ "$(wc -w <<< "$CALLS")" -gt 1 ] && [ -z "$W" ]; then
  echo "$S has GeMMX calls $CALLS: choose one with -k"; exit 2; fi
export NN_GLS_IDX_CALL="$IDX $CALLS"
REF=$QCNN/build/qcacc/rtl/${D}_stop_${S}_${C}ps
[ -d "$REF" ] && export NN_GLS_RTL=$REF
echo "[run_gls_qc] $D $S -> step $STEP (index $IDX), SAIF calls $CALLS, RTL ref ${NN_GLS_RTL:-none}"
exec "$QCNN/nn/gls/run_gls.sh" -H "$H" -m "$M" -c "$C" -s "$STEP" -t "${D}_${S}_${M}_${C}ps${K:+_c$K}" ${W:+-w "$W"}
