# impl/r6c QB_EST_RC "<ohm/um> <fF/um>" (sourced by place.tcl, cts_pre.tcl, route_pre.tcl): pre-route signal wire RC
# for estimate_parasitics -placement instead of the site's M3 values (1.397 ohm/um, 0.222 fF/um, tt).  Mechanism
# (r6c_g / r6c_p2 rpt/spread3_fail_1.txt): with M3 RC, repair_design buffered the nets that cross the 3.1-mm column
# array (S -> t2 north pins, act supply, f_y) every few 100 um; the buffers over the array are snapped to its south /
# west edge, where the S / WA templates fill the rows: 21.5 k 'wire' BUFFD16 piles, no room within 400 um, moved
# ~1.2 mm.  Over the blocks only M8 / M9 (0.054 ohm/um, 0.345 fF/um) are routable, so the long nets are a mix of M8/M9
# and M2-M7: e.g. QB_EST_RC "0.73 0.28" = half M8/M9, half M5.  Clock estimate (M5) unchanged.
if {[info exists ::env(QB_EST_RC)] && $::env(QB_EST_RC) ne ""} {
    lassign $::env(QB_EST_RC) _r _c
    foreach _k $::QC_CORNERS { set_wire_rc -signal -corner $_k -resistance [expr {$_r / 1000.0}] -capacitance [expr {$_c / 1000.0}] }
    qc_log "r6c: signal wire RC estimate $_r ohm/um $_c fF/um (QB_EST_RC)"
}
