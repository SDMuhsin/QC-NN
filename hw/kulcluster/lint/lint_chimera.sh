#!/usr/bin/env bash
# Verilator lint/elaboration of the full chimera SoC (chimera_top_wrapper) with TARGET_KULCLUSTER.
# Only the KUL slot uses its accelerator wrapper; the other 4 slots fall back to chimera's
# open snitch cluster (as upstream does when a TARGET_* is not set).
# Lint-only workaround (not a functional change): Verilator 5.044 rejects
# `localparam type x_t = some_type_t [N-1:0]` in cheshire's axi_rt_unit_top.sv; a copy with the
# four helper types rewritten as typedefs is used instead (build dir only, upstream untouched),
# and hyperbus' behavioural configurable_delay model is added.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
CHIM=$QCNN/third_party/chimera
W=$KUL_BUILD/chimera_lint; mkdir -p $W
cd $CHIM
bender script verilator -t snitch_cluster -t cv32a6_convolve -t cva6 -t rtl -t kulcluster > $W/chimera_kul.raw.f
RT=$(grep '/axi_rt_unit_top.sv$' $W/chimera_kul.raw.f)
sed -E 's/^\s*localparam type (\w+)\s*=\s*(.+);/  typedef \2 \1;/' "$RT" > $W/axi_rt_unit_top.sv
# hyperbus' configurable_delay is a tech cell; only its behavioural model (target `test`) exists
HB=$(bender path hyperbus)
{ sed "s#^$RT\$#$W/axi_rt_unit_top.sv#" $W/chimera_kul.raw.f; echo "$HB/models/configurable_delay.behav.sv"; } > $W/chimera_kul.f
cd $W
verilator --lint-only -Wno-fatal -Wno-lint -Wno-style -Wno-UNOPTFLAT -Wno-MULTIDRIVEN -Wno-BLKANDNBLK \
  --unroll-count 1024 -f chimera_kul.f --top-module ${TOP:-chimera_top_wrapper} > lint.log 2>&1 && rc=0 || rc=$?
grep -E "^%(Error|Warning)" lint.log | sed -E 's/:[0-9]+:[0-9]+:.*//' | sort | uniq -c | sort -rn | head -20
echo "lint rc=$rc  (log: $W/lint.log)"; exit $rc
