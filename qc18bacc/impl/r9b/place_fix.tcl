# R9b: finish the place step of a QB9_DMAP_STOP run (db/place_gpl.odb = global placement + both DRV repairs, before
# detailed placement) with the R9b fix: the repair buffers of the last DRV repair (dmap: 55 k um2 of buffers piled in
# the 26-um macro channels / halos and 43 k in the band, never re-spread) get an incremental global placement
# (QB9_GPL2_DENS, default PLACE_DENSITY + 0.06), then a DRV repair of the nets that move broke, dmap again, default
# detailed placement (no enlarged window), checkpoint db/place (the flow restarts at cts).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::T0 [clock seconds]
set ::STEPS {init floorplan pdn place cts route finish}
set_thread_count [qc_env QC_PNR_THREADS 8]
qc_read_liberty
read_db $::OUT/db/place_gpl.odb
set_dont_use $::QC_PNR_DONT_USE
read_sdc $::OUT/db/pdn.sdc
qc_set_rc
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
source $::env(QC_FLOW)/../../qc18bacc/impl/r9b/place_pre.tcl
set dens [qc_env QB9_GPL2_DENS [expr {[p PLACE_DENSITY] + 0.06}]]
global_placement -incremental -density $dens -pad_left [p PLACE_PAD] -pad_right [p PLACE_PAD] {*}[p GPL_ARGS]
estimate_parasitics -placement
qc_log "r9b fix: incremental gpl after the last DRV repair, density $dens [qc_util]"
qb_drv_orig
qb9_dmap
file rename -force $::OUT/rpt/dmap.txt $::OUT/rpt/dmap_fix.txt
write_db $::OUT/db/place_gpl2.odb
if {[catch {detailed_placement {*}[p DPL_ARGS]} e]} {
    # failed instances (DPL-0035 in the log) with their global-placement location and what covers it
    set blk [ord::get_db_block]; set u 2000.0; set f [open $::OUT/rpt/dpl_fail.txt w]
    set lf [open $::OUT/[qc_env QB9_LOG probe.log]]; set names {}
    foreach l [split [read $lf] \n] { if {[regexp {DPL-0035\]\s+(\S+)} $l -> n]} { lappend names $n } }
    close $lf
    set macs {}; foreach i [$blk getInsts] { if {[[$i getMaster] isBlock]} { lappend macs $i } }
    foreach n [lsort -unique $names] {
        set i [$blk findInst $n]; if {$i eq "NULL"} continue
        lassign [$i getLocation] x y; set on -
        foreach m $macs { set b [$m getBBox]; if {$x >= [$b xMin] && $x <= [$b xMax] && $y >= [$b yMin] && $y <= [$b yMax]} { set on [[$m getMaster] getName] } }
        puts $f [format "%s %s %.1f %.1f %s" $n [[$i getMaster] getName] [expr {$x / $u}] [expr {$y / $u}] $on]
    }
    close $f
    qc_log "r9b fix: detailed placement failed ($e), rpt/dpl_fail.txt"
    exit
}
check_placement
estimate_parasitics -placement
qc_report place
qc_summary "place [qc_util]"
qc_summary "place [join [qc_timing_lines place] { | }]"
qc_save place
exit
