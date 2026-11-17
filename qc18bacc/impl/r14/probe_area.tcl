# R14 probe (read-only): standard-cell area by floorplan region of <run>/db/<QB_DB> [place] (fp14 regions: gap,
# NW corner (x < X0, act top .. weights bottom), band (x >= X0, array top .. weights bottom), weight rows (y >= QB14_YN),
# over blocks) -> stdout lines "r14 area <region> <cells> <um2> <region um2> <util>".
read_db $::env(QC_PNR_OUT)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "place"}].odb
source $::env(QC_PNR_OUT)/mplace.tcl
set b [ord::get_db_block]; set u [$b getDefUnits]
lassign $::QB11_ACT ax1 ay1 ax2 ay2; set yt $::QB11_YT; set yn $::QB14_YN; set x0 $::QB14_X0; lassign $::QB14_DIE W H
array set a {}; array set n {}
foreach i [$b getInsts] {
    set m [$i getMaster]; if {[$m isBlock] || [$m getType] eq "BLOCK"} { continue }
    set bb [$i getBBox]; set x [expr {([$bb xMin] + [$bb xMax]) / 2.0 / $u}]; set y [expr {([$bb yMin] + [$bb yMax]) / 2.0 / $u}]
    if {$x < $x0 && $y < $ay1} { set r gap } elseif {$y < $yt} { set r overblock } elseif {$y < $yn} { set r [expr {$x < $x0 ? "nw_low" : "band"}] } else { set r [expr {$x < $x0 ? "nw_high" : "weights"}] }
    if {![info exists a($r)]} { set a($r) 0.0 }
    set a($r) [expr {$a($r) + [$m getWidth] * double([$m getHeight]) / $u / $u}]; incr n($r)
}
array set ra [list gap [expr {$x0 * ($ay1 - $::QB11_YH)}] band [expr {($W - $x0) * ($yn - $yt)}] nw_low [expr {$x0 * ($yn - $yt)}]]
foreach r [lsort [array names a]] { puts [format "r14 area %-9s %7d %10.0f %10s" $r $n($r) $a($r) [expr {[info exists ra($r)] ? [format "%.0f util %.2f" $ra($r) [expr {$a($r) / $ra($r)}]] : "-"}]] }
