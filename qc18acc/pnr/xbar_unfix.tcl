# Run after global placement (xbar_place.tcl wraps global_placement) and as PRE_CTS_TCL of qa4b.cfg (no-op then):
# the crossbar stage registers placed FIRM by xbar_place.tcl become PLACED again, so that the DRV / timing repair
# and the legalisations may resize / move them like any other cell.
set n 0
foreach i [[ord::get_db_block] getInsts] {
    if {![[$i getMaster] isBlock] && [$i getPlacementStatus] eq "FIRM" && [regexp {^(u_act/ar_rdata_reg|u_xbar/(sa|win)_reg)} [$i getName]]} {
        $i setPlacementStatus PLACED; incr n
    }
}
qc_log "xbar_unfix: $n crossbar registers FIRM -> PLACED"
