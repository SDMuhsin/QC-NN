# PRE_PLACE_TCL of blocks/hub/hub.cfg (results/r9b.md, r21.md, r35a.md bugs 1 + 4); one file for what impl/r35/hub_place_pre ->
# r21/place_pre -> r10b/place_pre -> r9b/place_pre -> r5b/pre_place made in a chain:
#   1. place/rm_buffers.tcl: max transition 0.4, remove_buffers, incremental gpl (density P(QB_GPL_INCR_DENS)) + 2nd DRV repair
#   2. partial placement blockages (max density 40 %) over the channels between the macro rows under the array (r9b_g0:
#      DPL-0036 cells = upsized glue drivers of the S-macro pins packed into the 27-um row-3 / row-4 channel) -> gpl spreads
#      that logic into the band instead of filling the channels
#   3. one more incremental gpl (density 0.65) + DRV repair after the place step's last DRV repair (r9b_g0: 55 k um2 of
#      repair buffers left in channels / halos, never re-spread)
#   4. design max fanout 32 (the column / act blocks place with 32; the SDC has 16)
#   5. a buffer at every hub IO port (inputs BUFFD2, outputs BUFFD8), after remove_buffers (it would delete them): the
#      abutted column -> hub inputs see one small buffer pin (was up to 333 fF) and the hub outputs (1 088 t2 pins on 3-mm
#      top trunks) have a strong driver
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/place/rm_buffers.tcl]
set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
set rows {}
foreach i [$blk getInsts] {
    if {![[$i getMaster] isBlock]} continue
    set b [$i getBBox]; if {[$b xMin] < 840 * $u} continue
    lappend rows [list [$b yMin] [$b yMax] [$b xMin] [$b xMax]]
}
array set R {}
foreach r $rows { lassign $r y0 y1 x0 x1; lappend R($y0) $r }
set ys [lsort -integer [array names R]]; set nb 0
for {set k 0} {$k < [llength $ys] - 1} {incr k} {
    set lo $R([lindex $ys $k]); set hi $R([lindex $ys [expr {$k + 1}]])
    set top [tcl::mathfunc::max {*}[lmap r $lo {lindex $r 1}]]; set bot [lindex $ys [expr {$k + 1}]]
    if {$bot - $top <= 0 || $bot - $top > 100 * $u} continue
    set xa [tcl::mathfunc::min {*}[lmap r [concat $lo $hi] {lindex $r 2}]]; set xb [tcl::mathfunc::max {*}[lmap r [concat $lo $hi] {lindex $r 3}]]
    set bk [odb::dbBlockage_create $blk $xa $top $xb $bot]
    $bk setMaxDensity 40; incr nb
    qc_log [format "r9b: channel blockage %.1f-%.1f x %.1f-%.1f um max density %s %%" [expr {$xa / double($u)}] [expr {$xb / double($u)}] [expr {$top / double($u)}] [expr {$bot / double($u)}] 40]
}
if {[info commands qb9_drv_prev] eq ""} {
    rename qc_repair_drv qb9_drv_prev
    proc qc_repair_drv {} {
        qb9_drv_prev
        set dens 0.65
        global_placement -incremental -density $dens -pad_left [p PLACE_PAD] -pad_right [p PLACE_PAD] {*}[p GPL_ARGS]
        estimate_parasitics -placement
        qc_log "r9b: incremental gpl after the last DRV repair, density $dens [qc_util]"
        qb_drv_orig
    }
}
set_max_fanout 32 [current_design]
qc_log "r21: max_fanout 32 max_transition 0.4"
set _t [clock seconds]; set _n0 [llength [[ord::get_db_block] getInsts]]
buffer_ports -inputs -buffer_cell BUFFD2
set _n1 [llength [[ord::get_db_block] getInsts]]
buffer_ports -outputs -buffer_cell BUFFD8
set _n2 [llength [[ord::get_db_block] getInsts]]
qc_log "r35 hub port buffers: inputs [expr {$_n1 - $_n0}] outputs [expr {$_n2 - $_n1}] ([expr {[clock seconds] - $_t}] s)"
