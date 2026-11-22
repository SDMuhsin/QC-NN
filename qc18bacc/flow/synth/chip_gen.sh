#!/usr/bin/env bash
# R5b top netlist sources (results/r5b.md): qb_chip of hw/tech/qb_chip_tech_r5e.f (R4b + QB_HEAD_FW 128) with qb_core
# replaced by synth/chip_core_blk.sv (8 x qb_col_blk, hw/tb/qb_colarr.sv).  As impl/r4/nocore.sh: qb_core.sv without
# the qb_core / qb_core_s modules -> <out>/qb_core_r5b.sv; file list <out>/qb_chip_r5b.f.  Output dir $1 (default
# $QC_BUILD/r5b_gen) so nothing generated lands in the repository.
set -eu
H=$(cd "$(dirname "$0")" && pwd); R=$H/../../hw; G=${1:-${QC_BUILD:-/tmp/$USER/qc18bacc/build}/r5b_gen}; mkdir -p "$G"
awk '/^module qb_core( |_s |_s\(| #|\()/ { skip = 1 } !skip { print } /^endmodule/ && skip { skip = 0 }' "$R/rtl/qb_core.sv" > "$G/qb_core_r5b.sv"
grep -c '^module' "$G/qb_core_r5b.sv"
{ sed -e "s#\.\./rtl/qb_core.sv#$G/qb_core_r5b.sv#" -e "s#^\.\./rtl/#$R/rtl/#" -e "s#^qb_mem_tech.sv#$R/tech/qb_mem_tech.sv#" \
      "$R/tech/qb_chip_tech_r5e.f"
  echo "$R/tb/qb_colarr.sv"; echo "$H/chip_core_blk.sv"; } > "$G/qb_chip_r5b.f"
echo "R5B_GEN $G/qb_chip_r5b.f"
