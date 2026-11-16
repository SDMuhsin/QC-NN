#!/bin/bash
# R7d: Yosys (oss-cad-suite, yosys-slang) generic-gate synthesis of a wb_blk wrapper, log in the current directory:
#   qc18bacc/impl/r7d/syn.sh <wrapper.sv> <tag> [defines...]     e.g. syn.sh rot.sv r_HQ HQ ; syn.sh rot.sv n_HQ HQ NOROT
# rot.sv: HQ | HQD | Z | SHZ (+ NOROT); wb_srd.sv: act-port S-read rotator; hqs.sv: HQ + S-read shared (estimate).
f=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); t=$2; shift 2; d=""
for x in "$@"; do d="$d -D$x"; done
printf 'read_slang --unroll-limit=1000000 %s %s\nsynth -top wb_blk -flatten\nabc -g AND,NAND,OR,NOR,XOR,XNOR,ANDNOT,ORNOT,MUX\nopt_clean\nstat\n' "$d" "$f" > $t.ys
${YOSYS:-/workspace/eda/opt/oss-cad-suite/bin/yosys} -m slang -q -l $t.log $t.ys > /dev/null 2>&1; echo "$t exit $?"
