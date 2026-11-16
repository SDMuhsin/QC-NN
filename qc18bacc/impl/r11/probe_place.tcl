# R11 probe (read-only): standard-cell area / count per floorplan region of db/<QB_DB>.odb (fp11.py regions), and the
# placement density of each region's free area.   QB_DB [place], QC_PNR_OUT = run dir.  -> stdout lines R11_REG
if {![info exists ::env(QB_DB)] || $::env(QB_DB) ne "none"} { read_db $::env(QC_PNR_OUT)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "place"}].odb }
source $::env(QC_PNR_OUT)/mplace.tcl
set u [[ord::get_db_tech] getDbUnitsPerMicron]
lassign $::QB11_ACT ax1 ay1 ax2 ay2
set yh $::QB11_YH; set yt $::QB11_YT
proc reg {x y} {
    upvar ax1 ax1 ay1 ay1 ax2 ax2 ay2 ay2 yh yh yt yt
    if {$y < $yh} { return hub }
    if {$x >= $ax1 && $x < $ax2 && $y >= $ay1 && $y < $ay2} { return act }
    if {$x >= 860 && $y < $yt} { return array }
    if {$x < 860 && $y < $ay1} { return gap }
    if {$x < 860} { return NWstrip }
    return north
}
array set A {}; array set N {}; array set F {}; array set P {}
foreach i [[ord::get_db_block] getInsts] {
    set m [$i getMaster]
    if {[$m isBlock]} {
        set b [$i getBBox]
        continue
    }
    if {[$m getType] ne "CORE" && ![string match CORE* [$m getType]]} { continue }
    set b [$i getBBox]
    set r [reg [expr {([$b xMin] + [$b xMax]) / 2.0 / $u}] [expr {([$b yMin] + [$b yMax]) / 2.0 / $u}]]
    set a [expr {[$b getDX] * [$b getDY] / double($u) / $u}]
    if {[catch {incr N($r)}]} { set N($r) 1 }
    if {$r in {hub act array}} {
        regsub {^((u_top_)?[A-Za-z]+[A-Za-z0-9]*_?[A-Za-z]*).*} [$i getName] {\1} k
        if {[catch {incr P($r,$k)}]} { set P($r,$k) 1 }
    }
    set A($r) [expr {([info exists A($r)] ? $A($r) : 0) + $a}]
}
foreach r [lsort [array names A]] { puts [format "R11_REG %-8s cells %7d area_mm2 %.4f" $r $N($r) [expr {$A($r) / 1e6}]] }
foreach r {hub act array} {
    set l {}
    foreach k [array names P $r,*] { lappend l [list [lindex [split $k ,] 1] $P($k)] }
    puts "R11_TRAP $r [lrange [lsort -integer -decreasing -index 1 $l] 0 7]"
}
