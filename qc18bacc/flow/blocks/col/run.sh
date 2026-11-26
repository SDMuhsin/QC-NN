#!/usr/bin/env bash
# Column block qb_col_blk: the shared block driver (common/block.sh: steps, variables, ECO loop) with the column's
# configuration (blocks/col/col.env + icc2.cfg; flow/README.md).  On the build host:
#   qc18bacc/flow/blocks/col/run.sh <pnr|eco|fill|calibre|post|views|signoff> <tag>     run dir $B/icc2/col/<tag>
# pnr first writes the floorplan pin DEF COL_PIN_DEF of the reference abstract COL_REFLEF (floorplan/abstract_pins.py, R72).
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$here/col.env"; . "$QBF/common/block.sh"
C=$QBF/signoff/calibre
BLK=col BLK_TOP=$COL_TOP BLK_SYN=$COL_SYN BLK_PERIOD=$COL_PERIOD BLK_CFG=$here/icc2.cfg BLK_PT=$QBF/signoff/pt/col_blk.tcl
BLK_FILL_SED="-f $C/fill_blk.sed" BLK_ODPO_SED="-f $C/odpo_blk.sed" BLK_LVS_SED="-f $C/lvs_case.sed" BLK_DRC_SED="-f $C/drc_blk.sed"
BLK_GATES=act_noise,abstract_abutment   # the act feedthrough's verdict gates (signoff/pt/col_blk.tcl, icc2.cfg P(ABUT_PAIR))
export COL_TOP COL_PIN_DEF   # read by icc2.cfg
blk_pre_pnr() { mkdir -p "$(dirname "$COL_PIN_DEF")" && "$PY" -I "$QBF/floorplan/abstract_pins.py" "$COL_REFLEF" "$COL_PIN_DEF"; }
blk_main "$@"
