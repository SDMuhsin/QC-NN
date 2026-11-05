#!/usr/bin/env bash
# Run every kernel in sim/kernels/ on one simulator and write a summary table.
#   sim/run_all.sh <vlt|vsim> [cfg]   ->  sim/results/summary_<sim>_<cfg>.txt
source "$(dirname "$0")/lib/common.sh"
SIM=${1:?usage: run_all.sh <vlt|vsim> [cfg]}
CFG=${2:-$SIM_CFG}
OUT=$QCNN_SIM/results/summary_${SIM}_${CFG}.txt
fail=0
{
  printf '# Snitch cluster (%s) on %s - %s\n' "$CFG" "$SIM" "$(date -u +%Y-%m-%dT%H:%MZ)"
  printf '%-10s %-6s %10s %12s  %s\n' kernel check total_cyc kernel_cyc "max_rel_err"
} > "$OUT"
for conf in "$QCNN_SIM"/kernels/*.conf; do
  k=$(basename "$conf" .conf)
  "$QCNN_SIM/run_kernel.sh" "$k" "$SIM" "$CFG" > /dev/null || fail=1
  r=$QCNN_SIM/results/${k}_${SIM}_${CFG}.txt
  chk=$(awk -F': ' '/^self-check/{print $2}' "$r" | cut -d' ' -f1)
  tot=$(awk '/cycles.*total/{print $3}' "$r")
  ker=$(awk '/cycles.*kernel/{print $3}' "$r")
  err=$(sed -n 's/.*max rel err \(.*\)/\1/p' "$r")
  printf '%-10s %-6s %10s %12s  %s\n' "$k" "$chk" "$tot" "${ker:--}" "${err:--}" >> "$OUT"
done
cat "$OUT"
exit $fail
