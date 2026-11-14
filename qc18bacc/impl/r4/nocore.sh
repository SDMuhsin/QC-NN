#!/usr/bin/env bash
# Per-hierarchy fallback (R4 stop rule): qb_chip with qb_core replaced by core_stub.sv (all inputs loaded, all outputs
# registered; its own area excluded) -> everything but the core;
# the core = 8 x the measured column (results/pnr_slice3.md qb_col_cwfp_b2, DC topo 1.65 ns).  Generates
# gen/qb_core_nocore.sv (qb_core.sv without the qb_core / qb_core_s modules, + the stub) and gen/qb_chip_nocore.f, then run.sh syn.
set -eu
H=$(cd "$(dirname "$0")" && pwd); R=$H/../../hw; G=$H/gen; mkdir -p "$G"
awk '/^module qb_core( |_s |_s\(| #|\()/ { skip = 1 } !skip { print } /^endmodule/ && skip { skip = 0 }' "$R/rtl/qb_core.sv" > "$G/qb_core_nocore.sv"
cat "$H/core_stub.sv" >> "$G/qb_core_nocore.sv"
grep -c '^module' "$G/qb_core_nocore.sv"
sed -e "s#\.\./rtl/qb_core.sv#$G/qb_core_nocore.sv#" -e "s#^\.\./rtl/#$R/rtl/#" -e "s#^qb_mem_tech.sv#$R/tech/qb_mem_tech.sv#" "$R/tech/qb_chip_tech.f" > "$G/qb_chip_nocore.f"
QB_FL=$G/qb_chip_nocore.f exec "$H/run.sh" syn qb_chip 1.65 r4_nocore
