#!/bin/bash
# R7g: Yosys (oss-cad-suite, yosys-slang) generic-gate synthesis of qb_head (FW 128, FC macro black box), log in cwd:
#   qc18bacc/impl/r7g/syn.sh <tag> <PCOL 0|1> [defines...]      e.g. syn.sh h0 0 ; syn.sh h1 1
# Per-module stat (qb_head top + qb_hpcol slices + qbcw_lane) after a hierarchical synth, then flattened totals.
H=$(cd "$(dirname "$0")" && pwd); R=$H/../../hw/rtl; t=$1; p=$2; shift 2; d=""
for x in "$@"; do d="$d -D$x"; done
printf 'read_slang --unroll-limit=1000000 -DSYNTHESIS %s -G FW=128 -G PCOL=%s --top qb_head %s %s %s\nhierarchy -top qb_head\nsynth -top qb_head\nabc -g AND,NAND,OR,NOR,XOR,XNOR,ANDNOT,ORNOT,MUX\nopt_clean\nstat\nflatten\nopt_clean\nstat\n' \
    "$d" "$p" "$R/qb_core.sv" "$R/qb_head.sv" "$H/rfsp_bb.sv" > $t.ys
${YOSYS:-/workspace/eda/opt/oss-cad-suite/bin/yosys} -m slang -q -l $t.log $t.ys > /dev/null 2>&1; echo "$t exit $?"
