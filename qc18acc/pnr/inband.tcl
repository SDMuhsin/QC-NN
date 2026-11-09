# Diagnostic (not part of the flow): fraction of the standard-cell area (non-macro, non-filler) whose centre lies
# inside the logic band y0..y1 of a checkpoint, and the area outside by block.
#   QC_PNR_OUT=<run dir> QA_STEP=place QA_Y0=<band low um> QA_Y1=<band high um> openroad -exit inband.tcl
read_db $::env(QC_PNR_OUT)/db/$::env(QA_STEP).odb
set blk [ord::get_db_block]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set y0 $::env(QA_Y0); set y1 $::env(QA_Y1)
set ain 0.0; set aout 0.0
array set bo {}
foreach i [$blk getInsts] {
    set m [$i getMaster]
    if {[$m isBlock] || [$m isFiller]} { continue }
    set b [$i getBBox]
    set a [expr {[$m getWidth] * [$m getHeight] / double($u) / $u}]
    set yc [expr {([$b yMin] + [$b yMax]) / 2.0 / $u}]
    if {$yc >= $y0 && $yc <= $y1} { set ain [expr {$ain + $a}] } else {
        set aout [expr {$aout + $a}]
        regexp {^([^/]+)} [$i getName] -> top
        if {[regexp {^u_array/g_col_\d+__g_row_\d+__u_pe} [$i getName]]} { set top u_array_pe }
        if {[regexp {^u_ppu/g_lane} [$i getName]]} { set top u_ppu_lane }
        set bo($top) [expr {[info exists bo($top)] ? $bo($top) + $a : $a}]
    }
}
puts [format "INBAND step %s band %.1f-%.1f in %.0f um2 out %.0f um2 out_frac %.3f" $::env(QA_STEP) $y0 $y1 $ain $aout [expr {$aout / ($ain + $aout)}]]
foreach k [lsort [array names bo]] { if {$bo($k) > 5000} { puts [format "INBAND   outside %-14s %.0f um2" $k $bo($k)] } }
