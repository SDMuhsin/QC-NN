# Antenna check of a routed QC18-ACC checkpoint in a separate OpenROAD session (the flow runs with ANTENNA_CHECK 0:
# repair_antennas segfaults in this build, results/pnr.md).  In the P&R run dir:
#   QC_FLOW=<repo>/flow/tsmc65 QC_PNR_OUT=$PWD QC_BUILD=... openroad -exit ant_check.tcl > ant.out
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count 4
set ::STEPS {init floorplan pdn place cts route_dr route finish}
qc_load route_dr
check_antennas -verbose
