#!/bin/bash
# R9c: Yosys (oss-cad-suite, yosys-slang) generic-gate synthesis of qb_prm (hw/rtl/qb_seq.sv) at the R4b tech depths
# (NFF 160 / NFW 32 / NFT 112), HPW 144, HSEL 1, R8a QB_PRM_BAR + QB_PRM_NUR; params macros black-boxed (impl/r7g/rfsp_bb.sv).
#   qc18bacc/impl/r9c/syn.sh <tag> <COL 0|1>        log <tag>.log in cwd (flattened stat)
H=$(cd "$(dirname "$0")" && pwd); R=$H/../../hw/rtl; t=$1; c=$2
printf 'read_slang --allow-use-before-declare --unroll-limit=1000000 -DSYNTHESIS -DQB_PRM_BAR -DQB_PRM_NUR -G NFF=160 -G NFW=32 -G NFT=112 -G HPW=144 -G HSEL=1 -G COL=%s --top qb_prm %s %s\nhierarchy -top qb_prm\nsynth -flatten -top qb_prm\nabc -g AND,NAND,OR,NOR,XOR,XNOR,ANDNOT,ORNOT,MUX\nopt_clean\nstat\n' \
    "$c" "$R/qb_seq.sv" "$H/../r7g/rfsp_bb.sv" > $t.ys
${YOSYS:-/workspace/eda/opt/oss-cad-suite/bin/yosys} -m slang -q -l $t.log $t.ys > /dev/null 2>&1; echo "$t exit $?"
