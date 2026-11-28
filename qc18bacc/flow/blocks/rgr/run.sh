#!/usr/bin/env bash
# Regression block qb_lane_n (one PPU lane, ~2.1 k DC cells, no macros): the shared block driver (common/block.sh) with
# the column's flow, Calibre decks and IO budget procs on a design whose pnr runs in minutes.  Every flow change passes
# it, from a snapshot of its commit (common/deploy.sh), before it may run on the column (flow/README.md).  On the build host:
#   qc18bacc/flow/blocks/rgr/run.sh <pnr|eco|fill|calibre|post|views|signoff> <tag>     run dir $B/icc2/rgr/<tag>
# Input: synth/run.sh rgr ($B/syn/$RGR_SYN).  pnr's floorplan step first writes the pin-only abstract <run>/pins.lef
# (floorplan/edge_pins.py) and its floorplan pin DEF (floorplan/abstract_pins.py, as the column's; common/block.sh blk_pins).
# Every step is regression-ready (README: pnr eco calibre post views signoff); PrimeTime: signoff/pt/rgr_blk.tcl (the
# generic block sign-off signoff/pt/blk.tcl with this block's IO budget and path classes); no opt-in verdict gates.
set -u
# (rgr.env before common/env.sh: its QB_ICC2_CORES default comes ahead of env.sh's; rgr.env reads nothing of env.sh)
here=$(cd "$(dirname "$0")" && pwd); . "$here/rgr.env"; . "$here/../../common/env.sh"; . "$QBF/common/block.sh"
C=$QBF/signoff/calibre
BLK=rgr BLK_TOP=$RGR_TOP BLK_SYN=$RGR_SYN BLK_PERIOD=$RGR_PERIOD BLK_CFG=$here/icc2.cfg BLK_PT=$QBF/signoff/pt/rgr_blk.tcl
BLK_FILL_SED="-f $C/fill_blk.sed" BLK_ODPO_SED="-f $C/odpo_blk.sed" BLK_LVS_SED="-f $C/lvs_case.sed" BLK_DRC_SED="-f $C/drc_blk.sed"
# (R109) one input of the block's own, so the regression runs the BLK_INPUTS code (common/block.sh blk_inputs / blk_input,
# common/regress.sh inputs): the DC database the netlist was written from, checked unchanged with the netlist below
BLK_INPUTS="ddc=$B/syn/$RGR_SYN/$RGR_TOP.ddc"
export RGR_TOP RGR_DIE QC_PNR_GUARD_HOLD QC_PNR_GUARD_TRAN   # read by icc2.cfg, init.tcl qb_guard
blk_pre_pnr() {
    local n; n=$(blk_input netlist) && blk_input ddc > /dev/null || return 1
    "$PY" -I "$QBF/floorplan/edge_pins.py" "$n" "$RGR_TOP" $RGR_DIE $RGR_PINS "$d/pins.lef" &&
    "$PY" -I "$QBF/floorplan/abstract_pins.py" "$d/pins.lef" "$1"
}
blk_main "$@"
