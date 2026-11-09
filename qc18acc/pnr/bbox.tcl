# Diagnostic (not part of the flow): placed bounding box / centroid of the PEs, PPU lanes and control blocks.
#   QC_FLOW=... QC_PNR_OUT=<run dir> QA_STEP=place openroad -exit bbox.tcl
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/[qc_env QA_STEP place].odb
set blk [ord::get_db_block]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
array set x0 {}; array set x1 {}; array set y0 {}; array set y1 {}; array set n {}; array set sx {}; array set sy {}
foreach i [$blk getInsts] {
    set nm [$i getName]
    if {[regexp {^(u_ppu/g_lane_\d+__u_lane|u_array/g_col_\d+__g_row_\d+__u_pe|u_seq|u_xbar|u_drain|u_head|u_agu)/} $nm -> g]} {
        set b [$i getBBox]; set x [expr {[$b xMin]/double($u)}]; set y [expr {[$b yMin]/double($u)}]
        if {![info exists n($g)]} { set n($g) 0; set x0($g) $x; set x1($g) $x; set y0($g) $y; set y1($g) $y; set sx($g) 0; set sy($g) 0 }
        incr n($g); set sx($g) [expr {$sx($g)+$x}]; set sy($g) [expr {$sy($g)+$y}]
        if {$x < $x0($g)} {set x0($g) $x}; if {$x > $x1($g)} {set x1($g) $x}; if {$y < $y0($g)} {set y0($g) $y}; if {$y > $y1($g)} {set y1($g) $y}
    }
}
foreach g [lsort -dictionary [array names n]] {
    # spread: rms distance from centroid
    puts [format "BB %-40s n %6d x %7.1f-%7.1f y %7.1f-%7.1f centroid %7.1f %7.1f" $g $n($g) $x0($g) $x1($g) $y0($g) $y1($g) [expr {$sx($g)/$n($g)}] [expr {$sy($g)/$n($g)}]]
}
