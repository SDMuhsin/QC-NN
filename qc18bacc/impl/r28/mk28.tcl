# R28: std-cell / row dump of a hub checkpoint for the DR marker classification (an28.py), on tau:
#   QC_PNR_OUT=<run> QB_DB [grt] QB28_OUT <file> openroad -exit mk28.tcl
# Writes "ROW y0 (um)" for the first row, "PITCH layer pitch offset dir" per routing track grid M1-M3, then per
# std instance (not BLOCK): master x0 y0 x1 y1 (um), nsig (ITerms on signal nets).
read_db $::env(QC_PNR_OUT)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "grt"}].odb
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]
set f [open $::env(QB28_OUT) w]
set r [lindex [$blk getRows] 0]; puts $f "ROW [expr {[lindex [$r getOrigin] 1] / $u}] [expr {[[$r getSite] getHeight] / $u}]"
foreach tg [$blk getTrackGrids] {
    set l [$tg getTechLayer]
    if {[lsearch {M1 M2 M3} [$l getName]] < 0} continue
    foreach d {X Y} {
        set n [expr {$d eq "X" ? [$tg getNumGridPatternsX] : [$tg getNumGridPatternsY]}]
        for {set i 0} {$i < $n} {incr i} {
            set p [expr {$d eq "X" ? [$tg getGridPatternX $i] : [$tg getGridPatternY $i]}]
            puts $f "PITCH [$l getName] $d [expr {[lindex $p 0] / $u}] [expr {[lindex $p 2] / $u}]"
        }
    }
}
foreach i [$blk getInsts] {
    set m [$i getMaster]
    if {[$m isBlock]} continue
    set b [$i getBBox]; set ns 0
    foreach it [$i getITerms] { set n [$it getNet]; if {$n ne "NULL" && [$n getSigType] eq "SIGNAL"} { incr ns } }
    puts $f "[$m getName] [expr {[$b xMin]/$u}] [expr {[$b yMin]/$u}] [expr {[$b xMax]/$u}] [expr {[$b yMax]/$u}] $ns"
}
close $f; puts "R28_MK done"
