#!/usr/bin/env bash
# Regression block qb_lane_n (one PPU lane, ~2.1 k DC cells, no macros): the shared block driver (common/block.sh) with
# the column's flow, Calibre decks and IO budget procs on a design whose pnr runs in minutes.  Every flow change passes
# it, from a snapshot of its commit (common/deploy.sh), before it may run on the column (flow/README.md).  On the build host:
#   qc18bacc/flow/blocks/rgr/run.sh <pnr|eco|fill|calibre|post|views|signoff> <tag>     run dir $B/icc2/rgr/<tag>
# Input: synth/run.sh rgr ($B/syn/$RGR_SYN).  pnr first writes the pin-only abstract RGR_PIN_LEF (floorplan/edge_pins.py)
# and its floorplan pin DEF RGR_PIN_DEF (floorplan/abstract_pins.py, as the column's).
# Regression-ready: pnr (+ fill).  eco / post need the block's PrimeTime script BLK_PT, not set yet (README: step 2), so
# they stop at once (set -u).
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/../../common/env.sh"; . "$here/rgr.env"; . "$QBF/common/block.sh"
C=$QBF/signoff/calibre
BLK=rgr BLK_TOP=$RGR_TOP BLK_SYN=$RGR_SYN BLK_PERIOD=$RGR_PERIOD BLK_CFG=$here/icc2.cfg
BLK_FILL_SED="-f $C/fill_blk.sed" BLK_ODPO_SED="-f $C/odpo_blk.sed" BLK_LVS_SED="-f $C/lvs_case.sed" BLK_DRC_SED="-f $C/drc_blk.sed"
export RGR_TOP RGR_DIE RGR_PIN_DEF   # read by icc2.cfg
blk_pre_pnr() {
    mkdir -p "$(dirname "$RGR_PIN_LEF")" "$(dirname "$RGR_PIN_DEF")" &&
    "$PY" -I "$QBF/floorplan/edge_pins.py" "$B/syn/$RGR_SYN/$RGR_TOP.v" "$RGR_TOP" $RGR_DIE $RGR_PINS "$RGR_PIN_LEF" &&
    "$PY" -I "$QBF/floorplan/abstract_pins.py" "$RGR_PIN_LEF" "$RGR_PIN_DEF"
}
blk_main "$@"
