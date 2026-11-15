# impl/r6b/run.sh prep: remove the DC buffer trees once, before the group placements (as impl/r5b/pre_place.tcl
# QB_RMBUF did inside the place step), so that grp_place.tcl and the place step see the same netlist.
# db/pdn.odb is kept as db/pdn0.odb and rewritten.
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 8]
set ::STEPS {init floorplan pdn place cts route finish}
if {![file exists $::OUT/db/pdn0.odb]} {
    file copy $::OUT/db/pdn.odb $::OUT/db/pdn0.odb; file copy $::OUT/db/pdn.sdc $::OUT/db/pdn0.sdc
} else {
    file copy -force $::OUT/db/pdn0.odb $::OUT/db/pdn.odb; file copy -force $::OUT/db/pdn0.sdc $::OUT/db/pdn.sdc
}
qc_load pdn
set n0 [llength [[ord::get_db_block] getInsts]]
# QB_RMBUF 0: keep DC's buffers (r6b_c)
if {[qc_env QB_RMBUF 1]} { remove_buffers }
qc_log "prep: remove_buffers [expr {$n0 - [llength [[ord::get_db_block] getInsts]]}] instances removed"
qc_save pdn
exit
