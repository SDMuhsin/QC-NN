# R36: abutment check of a top db (R36_DB [floorplan]): every net whose terminals are all hard-block pins (QB36_CLEANM
# masters, R0) and that has exactly 2 of them must have two pin shapes on one layer that touch / overlap (no top wire is
# routed for abutted nets).  Prints counts by master pair and up to 10 failing nets.  Run with impl/r29/or29.sh.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/[qc_env R36_DB floorplan].odb
set M [qc_env QB36_CLEANM {qb_col_blk qb_hub qb_act2_blk}]
set blk [ord::get_db_block]
proc pshapes {it} {
    set i [$it getInst]; lassign [$i getLocation] ox oy; set r {}
    foreach mp [[$it getMTerm] getMPins] { foreach g [$mp getGeometry] {
        set l [$g getTechLayer]; if {$l eq "NULL"} { continue }
        lappend r [list [$l getName] [expr {[$g xMin]+$ox}] [expr {[$g yMin]+$oy}] [expr {[$g xMax]+$ox}] [expr {[$g yMax]+$oy}]]
    } }
    return $r
}
array set ok {}; array set bad {}; set ex {}; set multi 0; set nets 0
foreach n [$blk getNets] {
    if {[$n getSigType] in {POWER GROUND}} { continue }
    if {[llength [$n getBTerms]]} { continue }
    set its [$n getITerms]; if {![llength $its]} { continue }
    set allb 1; foreach it $its { if {[[[$it getInst] getMaster] getName] ni $M} { set allb 0; break } }
    if {!$allb} { continue }
    incr nets
    if {[llength $its] != 2} { incr multi; continue }
    lassign $its a b
    set k "[[[$a getInst] getMaster] getName]-[[[$b getInst] getMaster] getName]"
    set t 0
    foreach sa [pshapes $a] { foreach sb [pshapes $b] {
        if {[lindex $sa 0] eq [lindex $sb 0] && [lindex $sa 1] <= [lindex $sb 3] && [lindex $sb 1] <= [lindex $sa 3] && [lindex $sa 2] <= [lindex $sb 4] && [lindex $sb 2] <= [lindex $sa 4]} { set t 1; break }
    } ; if {$t} { break } }
    if {$t} { incr ok($k) } else { incr bad($k); if {[llength $ex] < 10} { lappend ex "[$n getName] [$a getName] [lindex [pshapes $a] 0] | [$b getName] [lindex [pshapes $b] 0]" } }
}
puts "R36_ABUT block-only nets $nets (multi-terminal $multi)"
foreach k [lsort -unique [concat [array names ok] [array names bad]]] { puts "R36_ABUT $k touch [expr {[info exists ok($k)] ? $ok($k) : 0}] open [expr {[info exists bad($k)] ? $bad($k) : 0}]" }
foreach e $ex { puts "R36_ABUT_EX $e" }
exit
