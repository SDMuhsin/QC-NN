#!/bin/bash
# R34: default def2spef output (both copies) of the R34 file vs the R31 snapshot file must be identical (date line excluded)
d=/tmp/ckp908/qc18bacc/build/pnr/r33_fx; W=/tmp/ckp908/qc18bacc/r34
for esc in "" "--escape-divider"; do
  for v in r31_snap4 r34_snap6; do
    env -u QC_SPEF_ORFIX -u QC_SPEF_UNESC python3 -I /tmp/ckp908/qc18bacc/$v/flow/tsmc65/pnr/py/def2spef.py $d/out/qb_hub.def $d/out/qb_hub.conn $d/rc/tt.txt $W/idt.spef $esc > /dev/null
    echo "IDT esc=$esc $v $(grep -v "^\*DATE" $W/idt.spef | md5sum)"; rm -f $W/idt.spef
  done
done
