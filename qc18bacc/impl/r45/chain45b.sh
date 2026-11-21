#!/usr/bin/env bash
# R45: after chain45.sh: column tt ETM without input driving cells (etmnodrv45.tcl) and the outlier count of both ETMs.
set -u
R45=${R45:-$HOME/r45}; cd "$R45" || exit 1
while ! grep -q CHAIN45_DONE chain45.out 2>/dev/null; do sleep 30; done
mkdir -p pt2 && cd pt2
R45_ETMOUT=$R45/pt2/etm "$R45/pt45.sh" /tmp/ckp908/qc18bacc/build/pnr/r35_colb tt "$R45/etmnodrv45.tcl" "$R45/pt2/etmnodrv_tt.log" 6.5
P=/tmp/ckp908/tools/env/bin/python3
echo "== production tt ETM"; $P -I "$R45/etmout45.py" /tmp/ckp908/qc18bacc/build/pnr/r35_colb/out/etm/qb_col_blk_tt.lib 2.0 'act[2911]' 'act[2910]' 'pf[507]'
echo "== no-driving-cell tt ETM"; $P -I "$R45/etmout45.py" "$R45/pt2/etm/qb_col_blk_tt.lib" 2.0 'act[2911]' 'act[2910]' 'pf[507]'
echo CHAIN45B_DONE
