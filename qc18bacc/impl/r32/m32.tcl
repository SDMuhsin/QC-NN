# R32 placement metrics (sourced into a loaded OpenROAD db): r32_metrics <tag>
#   fo1: Manhattan driver->sink distance of 2-pin signal nets between std cells (p50 / p90 / mean, um)
#   pcol: cells of u_head/g_pcol_4__u_pc: count, cell area, bbox area, fill = area / bbox
#   intadd_104 chain of g_pcol_4: mean consecutive-cell distance
proc r32_metrics {tag} {
    set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
    set d {}
    foreach n [$blk getNets] {
        if {[$n getSigType] ne "SIGNAL" || [llength [$n getBTerms]]} continue
        set its [$n getITerms]
        if {[llength $its] != 2} continue
        set a [lindex $its 0]; set b [lindex $its 1]
        if {[[[$a getInst] getMaster] isBlock] || [[[$b getInst] getMaster] isBlock]} continue
        lassign [[$a getInst] getLocation] x1 y1; lassign [[$b getInst] getLocation] x2 y2
        lappend d [expr {(abs($x1 - $x2) + abs($y1 - $y2)) / $u}]
    }
    set d [lsort -real $d]; set n [llength $d]
    set s 0.0; foreach v $d { set s [expr {$s + $v}] }
    set r [format "R32M %s fo1 n %d p50 %.1f p90 %.1f mean %.1f" $tag $n [lindex $d [expr {$n / 2}]] [lindex $d [expr {$n * 9 / 10}]] [expr {$s / max(1, $n)}]]
    set x0 1e12; set y0 1e12; set x1 -1e12; set y1 -1e12; set a 0.0; set c 0
    foreach i [$blk getInsts] {
        if {![string match u_head/g_pcol_4__u_pc/* [$i getName]]} continue
        set m [$i getMaster]; incr c; set a [expr {$a + [$m getWidth] * [$m getHeight] / $u / $u}]
        set bb [$i getBBox]
        set x0 [expr {min($x0, [$bb xMin] / $u)}]; set y0 [expr {min($y0, [$bb yMin] / $u)}]
        set x1 [expr {max($x1, [$bb xMax] / $u)}]; set y1 [expr {max($y1, [$bb yMax] / $u)}]
    }
    if {$c} { append r [format " | pcol4 cells %d area %.0f bbox %.0f x %.0f fill %.3f" $c $a [expr {$x1 - $x0}] [expr {$y1 - $y0}] [expr {$a / max(1.0, ($x1 - $x0) * ($y1 - $y0))}]] }
    set pv {}; set dd 0.0; set k 0
    foreach j {17 16 15 14 13 12 11 10 9 8 7 6 5 4 3} {
        set i [$blk findInst u_head/g_pcol_4__u_pc/intadd_104_U$j]; if {$i eq "NULL"} continue
        lassign [$i getLocation] x y
        if {$pv ne ""} { set dd [expr {$dd + (abs($x - [lindex $pv 0]) + abs($y - [lindex $pv 1])) / $u}]; incr k }
        set pv [list $x $y]
    }
    if {$k} { append r [format " | chain mean step %.1f um (%d)" [expr {$dd / $k}] $k] }
    if {![catch {set ws [sta::worst_slack_cmd max]}]} { append r [format " | wns %.3f" [expr {$ws * 1e9}]] }
    puts $r; flush stdout
}
