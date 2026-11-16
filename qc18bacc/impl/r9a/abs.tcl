# R9a abstracts of the routed qb_act2_blk (results/r9a.md), run by run.sh abs in the P&R run dir:
#   * write_abstract_lef -bloat_factor 0 (exact shapes) -> $QB9_ABS_OUT/qb_act2_blk.lef; the die box is printed
#     (QB9_DIE) so that lef_size.py can set SIZE to the die (R7c's LEF SIZE was the shape bbox, 2 413.965 vs 2 420)
#   * check_antennas on the routed db
#   * abutment check: every act[b] pin on the east die edge, same layer and y (block y + QB7_YOFF) as column 0's act[b]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_read_liberty
read_db $::OUT/db/route_dr.odb
set blk [ord::get_db_block]; set die [$blk getDieArea]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
set W [expr {[$die dx] / double($u)}]; set H [expr {[$die dy] / double($u)}]
puts [format "QB9_DIE %.3f %.3f" $W $H]
set o $::env(QB9_ABS_OUT)
write_abstract_lef -bloat_factor 0 $o/qb_act2_blk.lef
set yoff [qc_env QB7_YOFF [expr {3110.0 - $H}]]
array set col {}
set f [open $::env(QB7_COLPINS)]
while {[gets $f line] >= 0} { if {[llength $line] >= 6} { lassign $line b ly x0 y0 x1 y1; set col($b) [list $ly $y0 $y1] } }
close $f
set ok 0; set bad 0; set n 0
foreach bt [$blk getBTerms] {
    if {![regexp {^act\[(\d+)\]$} [$bt getName] -> b]} { continue }
    incr n
    set bx [lindex [[lindex [$bt getBPins] 0] getBoxes] 0]
    lassign $col($b) ly y0 y1
    if {[[$bx getTechLayer] getName] eq $ly && [$bx xMax] == [$die xMax] &&
        abs([$bx yMin] / double($u) + $yoff - $y0) < 0.0011 && abs([$bx yMax] / double($u) + $yoff - $y1) < 0.0011} { incr ok } else { incr bad }
}
puts "QB9_ABUT act pins $n match_column0 $ok bad $bad yoff $yoff"
set ns 0; set nn 0; set nw 0; set ne 0
foreach bt [$blk getBTerms] {
    if {[$bt getSigType] ne "SIGNAL" && [$bt getName] ne "clk"} { continue }
    set bp [lindex [$bt getBPins] 0]; if {$bp eq ""} { continue }
    set bx [lindex [$bp getBoxes] 0]
    if {[$bx yMin] == [$die yMin]} { incr ns } elseif {[$bx yMax] == [$die yMax]} { incr nn } elseif {[$bx xMax] == [$die xMax]} { incr ne } else { incr nw }
}
puts "QB9_PINS south $ns north $nn east $ne west $nw"
if {[catch {check_antennas -report_file $::OUT/rpt/antenna_abs.rpt} e]} { puts "QB9_ANT error $e" } else { puts "QB9_ANT done" }
exit
