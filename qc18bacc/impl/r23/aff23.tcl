# R23 (results/r23.md): connectivity + placement dump of a placed hub checkpoint (QB_DB [place]) for aff23.py
# (column-order feasibility estimate).  Read-only on the run dir; output -> $QB23_OUT:
#   I <id> <master> <cx> <cy> <isMacro 0|1> <macro inst name or ->      every instance (centre, um)
#   N <net> <inst ids ...> | ports as p<x>:<y>                         every SIGNAL net
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env QB_DB place].odb
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set f [open $::env(QB23_OUT) w]
set blk [ord::get_db_block]
set k 0
foreach i [$blk getInsts] {
    set m [$i getMaster]; set b [$i getBBox]; set id($i) $k
    set mac [expr {[$m isBlock] ? 1 : 0}]
    puts $f [format "I %d %s %.1f %.1f %d %s" $k [$m getName] [expr {([$b xMin] + [$b xMax]) / 2.0 / $u}] \
        [expr {([$b yMin] + [$b yMax]) / 2.0 / $u}] $mac [expr {$mac ? [$i getName] : "-"}]]
    incr k
}
foreach n [$blk getNets] {
    if {[$n getSigType] ne "SIGNAL"} { continue }
    set t {}
    foreach it [$n getITerms] { lappend t $id([$it getInst]) }
    foreach bt [$n getBTerms] {
        set bb [$bt getBBox]
        lappend t [format "p%.1f:%.1f" [expr {([$bb xMin] + [$bb xMax]) / 2.0 / $u}] [expr {([$bb yMin] + [$bb yMax]) / 2.0 / $u}]]
    }
    if {[llength $t] > 1} { puts $f "N [$n getName] [join $t]" }
}
close $f
puts "R23_AFF done"
exit
