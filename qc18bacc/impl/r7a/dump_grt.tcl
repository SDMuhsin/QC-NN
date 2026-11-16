# impl/r7a (read-only): text dump of a routed checkpoint for impl/r7a/classify.py.  Reuses impl/r6a/net_dump.tcl
# (I / N lines, signal nets) with exit deferred, then adds to QB_OUT:
#   C <net> <driver> <sink> ...          clock nets (sig type CLOCK; skipped by net_dump.tcl)
#   B <inst> <master> <x0> <y0> <x1> <y1>  bbox (um) of every block / macro instance
#   L <layer> <dir> <level> <pitch_x um> <pitch_y um> <n_x> <n_y>   routing layers + track grid
#   G <nx> <ny> <gx0 um> <gx1 um> <gy0 um> <gy1 um>     gcell grid summary; D <x0> <y0> <x1> <y1> die (um)
# env: QB_RUN, QB_DB (grt), QB_OUT, QB_R6A (impl/r6a dir)
rename exit qb7_exit
proc exit {args} {}
source $::env(QB_R6A)/net_dump.tcl
set fo [open $::env(QB_OUT) a]
foreach net [$blk getNets] {
    if {[$net getSigType] ne "CLOCK"} continue
    set d -; set s {}
    foreach it [$net getITerms] {
        set t [[$it getInst] getName]
        if {[$it isOutputSignal]} { set d $t } elseif {[$it isInputSignal]} { lappend s $t }
    }
    foreach bt [$net getBTerms] { if {[$bt getIoType] eq "INPUT"} { set d PORT:[$bt getName] } }
    puts $fo "C [$net getName] $d [join $s { }]"
}
foreach i [$blk getInsts] {
    if {![[$i getMaster] isBlock]} continue
    set b [$i getBBox]
    puts $fo [format "B %s %s %.1f %.1f %.1f %.1f" [$i getName] [[$i getMaster] getName] [expr {[$b xMin]/$u}] [expr {[$b yMin]/$u}] [expr {[$b xMax]/$u}] [expr {[$b yMax]/$u}]]
}
foreach l [[ord::get_db_tech] getLayers] {
    if {[$l getType] ne "ROUTING"} continue
    set tg [$blk findTrackGrid $l]
    set px 0; set py 0; set nx 0; set ny 0
    if {$tg ne "NULL" && $tg ne ""} {
        set gx [$tg getGridX]; set gy [$tg getGridY]
        set nx [llength $gx]; set ny [llength $gy]
        if {$nx > 1} { set px [expr {([lindex $gx 1] - [lindex $gx 0]) / $u}] }
        if {$ny > 1} { set py [expr {([lindex $gy 1] - [lindex $gy 0]) / $u}] }
    }
    puts $fo "L [$l getName] [$l getDirection] [$l getRoutingLevel] $px $py $nx $ny"
}
set g [$blk getGCellGrid]
if {$g ne "NULL" && $g ne ""} {
    set gx [$g getGridX]; set gy [$g getGridY]
    puts $fo "G [llength $gx] [llength $gy] [expr {[lindex $gx 0]/$u}] [expr {[lindex $gx end]/$u}] [expr {[lindex $gy 0]/$u}] [expr {[lindex $gy end]/$u}]"
}
set da [$blk getDieArea]
puts $fo "D [expr {[$da xMin]/$u}] [expr {[$da yMin]/$u}] [expr {[$da xMax]/$u}] [expr {[$da yMax]/$u}]"
close $fo
puts "R7A_DUMP done"
qb7_exit
