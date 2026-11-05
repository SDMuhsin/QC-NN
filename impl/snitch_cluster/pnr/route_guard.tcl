# Sourced at the end of pre_route.tcl (or alone as PRE_ROUTE_TCL when restarting the route step from db/cts_opt.odb):
# the antenna checker of this OpenROAD build crashed in repair_antennas on this design (SIGSEGV in
# odb::dbWireGraph::decode), and check_antennas (route.tcl, after detailed routing) uses the same code.  So
# check_antennas first writes the routed checkpoint db/route.odb; after a crash the run continues with
# QC_PNR_FROM=finish.
if {[llength [info commands sn_check_antennas_orig]] == 0} { rename check_antennas sn_check_antennas_orig }
proc check_antennas {args} {
    qc_log "route_guard: checkpoint db/route.odb before check_antennas"
    qc_save route
    sn_check_antennas_orig {*}$args
}
