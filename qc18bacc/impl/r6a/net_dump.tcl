# impl/r6a (H2): dump instances and signal-net connectivity of a chip checkpoint as text for impl/r6a/cuts.py.
# QB_RUN, QB_DB (default place), QB_OUT.  Lines:
#   I <inst> <master> <area um2> <x um> <y um>         (every instance)
#   N <net> <driver> <sink> ...   (signal nets; buffers / inverters kept); a terminal = <inst> (standard cell),
#     <inst>:<pin>@<edge N/S/E/W> (block / macro pin, nearest instance edge) or PORT:<name> (chip IO)
read_db $::env(QB_RUN)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "place"}].odb
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set fo [open $::env(QB_OUT) w]
foreach i [$blk getInsts] {
    set m [$i getMaster]; set b [$i getBBox]
    puts $fo "I [$i getName] [$m getName] [format %.3f [expr {[$m getWidth] / $u * [$m getHeight] / $u}]] [format %.1f [expr {([$b xMin] + [$b xMax]) / 2 / $u}]] [format %.1f [expr {([$b yMin] + [$b yMax]) / 2 / $u}]]"
}
foreach net [$blk getNets] {
    set st [$net getSigType]; if {$st eq "POWER" || $st eq "GROUND" || $st eq "CLOCK"} continue
    set d ""; set s {}
    foreach it [$net getITerms] {
        set i [$it getInst]; set t [$i getName]
        if {[[$i getMaster] isBlock]} {
            set ib [$i getBBox]; set pb [$it getBBox]
            set px [expr {([$pb xMin] + [$pb xMax]) / 2}]; set py [expr {([$pb yMin] + [$pb yMax]) / 2}]
            set dl [list [list W [expr {$px - [$ib xMin]}]] [list E [expr {[$ib xMax] - $px}]] [list S [expr {$py - [$ib yMin]}]] [list N [expr {[$ib yMax] - $py}]]]
            set e [lindex [lsort -integer -index 1 $dl] 0 0]
            set t "$t:[[$it getMTerm] getName]@$e"
        }
        if {[$it isOutputSignal]} { set d $t } elseif {[$it isInputSignal]} { lappend s $t }
    }
    foreach bt [$net getBTerms] {
        if {[$bt getIoType] eq "INPUT"} { set d PORT:[$bt getName] } else { lappend s PORT:[$bt getName] }
    }
    if {$d eq ""} { set d - }
    puts $fo "N [$net getName] $d [join $s { }]"
}
close $fo
puts "NET_DUMP done"
exit
