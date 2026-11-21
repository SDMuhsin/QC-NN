# R35 diagnostic (no db written): top pdn db -> pre_place (as the flow) -> global_placement -overflow QB35_OVF [0.35];
# std-cell area vs free row area in 100-um bins, worst bins printed (R35_GPLD lines)
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load pdn
set_thread_count 8
source $::QB_R5B/pre_place.tcl
catch { global_placement -density [p PLACE_DENSITY] -overflow [qc_env QB35_OVF 0.35] {*}[qc_env QB35_GARGS ""] } e
puts "R35_GPLD gpl: $e"
set blk [ord::get_db_block]; set u [$blk getDefUnits]; set B [expr {100 * $u}]
array set a {}; array set r {}; array set nm {}
foreach row [$blk getRows] { set bb [$row getBBox]
    for {set x [$bb xMin]} {$x < [$bb xMax]} {incr x $B} { set k "[expr {$x / $B}],[expr {[$bb yMin] / $B}]"
        set w [expr {min([$bb xMax], ($x / $B + 1) * $B) - $x}]; set r($k) [expr {[info exists r($k)] ? $r($k) + $w * [$bb dy] : $w * [$bb dy]}] } }
foreach i [$blk getInsts] { set m [$i getMaster]; if {[$m isBlock] || [string match FILL* [$m getName]]} continue
    lassign [$i getLocation] x y; set k "[expr {$x / $B}],[expr {$y / $B}]"
    set a($k) [expr {[info exists a($k)] ? $a($k) + [$m getWidth] * [$m getHeight] : [$m getWidth] * [$m getHeight]}]
    if {![info exists nm($k)]} { set nm($k) [$i getName] } }
set L {}
foreach k [array names a] { set f [expr {[info exists r($k)] ? $r($k) : 0}]; lappend L [list $k [expr {$a($k) / double($u*$u)}] [expr {$f / double($u*$u)}] $nm($k)] }
set n 0; foreach e [lsort -decreasing -real -index 1 $L] { if {[incr n] > 25} break; puts [format "R35_GPLD bin %s cell_um2 %.0f row_um2 %.0f e.g. %s" {*}$e] }
set tot 0; set over 0; foreach e $L { set tot [expr {$tot + [lindex $e 1]}]; if {[lindex $e 1] > [lindex $e 2]} { set over [expr {$over + [lindex $e 1] - [lindex $e 2]}] } }
puts [format "R35_GPLD total_cell_um2 %.0f excess_over_rows_um2 %.0f" $tot $over]
exit
