# PRE_PLACE_TCL of impl/r6c/chip.cfg: impl/r6b/place.tcl, then QB_SPREAD3 1 replaces spread2 by spread3.tcl
# (spread3 runs wherever the R6b hooks call spread2: before the first detailed placement with QB_SNAP + QB_SPREAD 2,
# and before every later one with QB_SPREAD_ALL 1).
source $::QB_R6B/place.tcl
if {[qb_env QB_SPREAD3 0]} { source $::QB_R6C/spread3.tcl }
# QB_SNAP3 1: row-aware snap (snap3.tcl) instead of impl/r6b qb6_snap (the R6b spread wrapper calls qb6_snap_orig)
if {[qb_env QB_SNAP3 0] && [qb_env QB_SNAP 0]} {
    source $::QB_R6C/snap3.tcl
    if {[info commands qb6_snap_orig] ne ""} { rename qb6_snap_orig {}; rename qb6_snap qb6_snap_orig; proc qb6_snap {} { qb6_snap_orig; qb6_spread } }
}
source $::QB_R6C/est_rc.tcl
