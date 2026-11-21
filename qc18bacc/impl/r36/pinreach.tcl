# R36 gpl-divergence probe: block / macro pins that connect to top std cells or chip IOs, binned by whether a std-cell
# row lies within R36_D [20] um of the pin (reachable) or not (pin enclosed by other blocks: its top cells are pulled
# to a point where nothing can be placed).  Reads R36_DB [pdn].  Prints counts by master / side and examples.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/[qc_env R36_DB pdn].odb
set blk [ord::get_db_block]; set u [$blk getDefUnits]; set D [expr {[qc_env R36_D 20] * $u}]
# row index: list of row bboxes bucketed by 100-um y
array set rb {}
foreach r [$blk getRows] { set b [$r getBBox]; for {set k [expr {([$b yMin]-$D)/(100*$u)}]} {$k <= ([$b yMax]+$D)/(100*$u)} {incr k} { lappend rb($k) [list [$b xMin] [$b yMin] [$b xMax] [$b yMax]] } }
proc near {x y} {
    global rb D u
    set k [expr {$y / (100*$u)}]; if {![info exists rb($k)]} { return 0 }
    foreach b $rb($k) { if {$x >= [lindex $b 0]-$D && $x <= [lindex $b 2]+$D && $y >= [lindex $b 1]-$D && $y <= [lindex $b 3]+$D} { return 1 } }
    return 0
}
array set pc {}; set ex {}; set cells 0; array set stuck {}
foreach i [$blk getInsts] {
    set m [$i getMaster]; if {![$m isBlock]} { continue }
    lassign [$i getLocation] ox oy; set mn [$m getName]
    foreach it [$i getITerms] {
        set n [$it getNet]; if {$n eq "NULL" || [$n getSigType] ne "SIGNAL"} { continue }
        set std 0; foreach o [$n getITerms] { if {![[[$o getInst] getMaster] isBlock]} { incr std } }
        if {!$std && ![llength [$n getBTerms]]} { continue }
        set b [[lindex [[$it getMTerm] getMPins] 0] getBBox]
        set x [expr {$ox + ([$b xMin]+[$b xMax])/2}]; set y [expr {$oy + ([$b yMin]+[$b yMax])/2}]
        set ok [near $x $y]
        incr pc($mn,$ok)
        if {!$ok} { incr cells $std; if {[llength $ex] < 12} { lappend ex "[$i getName]/[[$it getMTerm] getName] at [expr {$x/$u}] [expr {$y/$u}] net [$n getName] std_terms $std" }
            set k "[expr {int($x/$u/200)*200}],[expr {int($y/$u/200)*200}]"; incr stuck($k) }
    }
}
foreach k [lsort [array names pc]] { puts "R36_REACH $k $pc($k)" }
puts "R36_REACH unreachable pins drive / load $cells top std terminals"
foreach k [lsort [array names stuck]] { puts "R36_REACH stuck_bin_200um $k $stuck($k)" }
foreach e $ex { puts "R36_REACH_EX $e" }
exit
