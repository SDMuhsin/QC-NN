# Diagnostic (not part of the flow): global-route congestion of a routed / post-GRT checkpoint, and the placement
# density behind it.  Reads db/<QA_STEP>.odb (default route_dr), re-runs global_route -verbose with the flow's layer
# adjustment (QA_GR_ADJ, default the config's GR_ADJUST) writing $OUT/rpt/diag_grt.guide and the congestion report
# rpt/diag_gr_congestion.rpt, and prints per 50-um tile (QA_TILE) the standard-cell utilisation (fillers excluded)
# and the dominant block, for the tiles of the window QA_WIN {x0 y0 x1 y1} (um).
#   QC_FLOW=... QC_PNR_OUT=<run dir> [QA_STEP=..] [QA_GR_ADJ=..] openroad -exit gr_diag.tcl
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 8]
qc_read_liberty
read_db $::OUT/db/[qc_env QA_STEP route_dr].odb
set blk [ord::get_db_block]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set t [qc_env QA_TILE 50]
set win [qc_env QA_WIN {1300 1000 2100 2100}]
lassign $win wx0 wy0 wx1 wy1
array set area {}; array set blkc {}
foreach i [$blk getInsts] {
    set m [$i getMaster]
    if {[$m isBlock]} { continue }
    set nm [$i getName]
    if {[string match FILLER* $nm] || [string match *DCAP* [$m getName]]} { continue }
    set b [$i getBBox]
    set cx [expr {([$b xMin] + [$b xMax]) / 2.0 / $u}]; set cy [expr {([$b yMin] + [$b yMax]) / 2.0 / $u}]
    if {$cx < $wx0 || $cx > $wx1 || $cy < $wy0 || $cy > $wy1} { continue }
    set k [expr {int($cx / $t)}],[expr {int($cy / $t)}]
    set a [expr {double([$m getWidth]) * [$m getHeight] / $u / $u}]
    if {![info exists area($k)]} { set area($k) 0.0 }
    set area($k) [expr {$area($k) + $a}]
    regexp {^([^/]+(/g_col_\d+__g_row_\d+__u_pe)?)} $nm -> h
    if {![regexp {/} $nm]} { set h top }
    if {![info exists blkc($k,$h)]} { set blkc($k,$h) 0.0 }
    set blkc($k,$h) [expr {$blkc($k,$h) + $a}]
}
foreach k [lsort -dictionary [array names area]] {
    set best ""; set bv 0
    foreach kk [array names blkc $k,*] { if {$blkc($kk) > $bv} { set bv $blkc($kk); set best [lindex [split $kk ,] 2] } }
    lassign [split $k ,] ix iy
    puts [format "TILE x %5d y %5d util %.3f top %-36s %.3f" [expr {$ix*$t}] [expr {$iy*$t}] [expr {$area($k)/($t*$t)}] $best [expr {$bv/($t*$t)}]]
}
qc_log "tiles done"
# global_route skips nets that already carry a dbWire: drop the detailed-route wires of the signal nets
set nw 0
foreach net [$blk getNets] {
    if {[$net isSpecial]} { continue }
    set w [$net getWire]
    if {$w ne "NULL" && $w ne ""} { odb::dbWire_destroy $w; incr nw }
}
qc_log "wires removed: $nw"
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [qc_env QA_GR_ADJ [p GR_ADJUST]]
global_route -guide_file $::OUT/rpt/diag_grt.guide -congestion_iterations [p GR_ITER] -verbose -allow_congestion \
    -congestion_report_file $::OUT/rpt/diag_gr_congestion.rpt
qc_log "grt done"
