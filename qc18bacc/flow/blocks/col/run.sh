#!/usr/bin/env bash
# Column block qb_col_blk: the shared block driver (common/block.sh: steps, variables, ECO loop) with the column's
# configuration (blocks/col/col.env + icc2.cfg; flow/README.md).  On the build host:
#   qc18bacc/flow/blocks/col/run.sh <pnr|eco|fill|calibre|post|views|signoff> <tag>     run dir $B/icc2/col/<tag>
# pnr's floorplan step first writes the floorplan pin DEF of the reference abstract COL_REFLEF (floorplan/abstract_pins.py,
# R72) into the run dir (common/block.sh blk_pins).
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$here/col.env"; . "$QBF/common/block.sh"
C=$QBF/signoff/calibre
BLK=col BLK_TOP=$COL_TOP BLK_SYN=$COL_SYN BLK_PERIOD=$COL_PERIOD BLK_CFG=$here/icc2.cfg BLK_PT=$QBF/signoff/pt/col_blk.tcl
BLK_FILL_SED="-f $C/fill_blk.sed" BLK_ODPO_SED="-f $C/odpo_blk.sed" BLK_LVS_SED="-f $C/lvs_case.sed" BLK_DRC_SED="-f $C/drc_blk.sed"
BLK_GATES=act_noise,abstract_abutment   # the act feedthrough's verdict gates (signoff/pt/col_blk.tcl, icc2.cfg P(ABUT_PAIR))
BLK_INPUTS="reflef=$COL_REFLEF"         # the pin reference outside the snapshot, recorded by common/block.sh blk_inputs
export COL_TOP QC_PNR_GUARD_HOLD QC_PNR_GUARD_TRAN   # read by icc2.cfg, init.tcl qb_guard
blk_pre_pnr() { local r; r=$(blk_input reflef) && "$PY" -I "$QBF/floorplan/abstract_pins.py" "$r" "$1"; }
blk_main "$@"
