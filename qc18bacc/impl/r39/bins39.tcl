# R39 probe (read-only): standard-cell area per 50-um bin of <run>/db/<QB_DB [place]>.odb, bins whose area is free of
# hard blocks / macros only; prints the bin count above 0.70 / 0.85 / 0.95 utilisation and the 12 densest bins
# ("R39BIN x y util cells", bin lower-left um).  Run with impl/r29/or29.sh <tag> <this> <log> (R29_DB) or plain openroad.
read_db $::env(QC_PNR_OUT)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "place"}].odb
set b [ord::get_db_block]; set u [$b getDefUnits]; set G [expr {50 * $u}]
array set A {}; array set N {}; array set M {}
foreach i [$b getInsts] {
    set m [$i getMaster]; set bb [$i getBBox]
    if {[$m isBlock] || [$m getType] eq "BLOCK"} {
        for {set x [expr {[$bb xMin] / $G}]} {$x <= ([$bb xMax] - 1) / $G} {incr x} {
            for {set y [expr {[$bb yMin] / $G}]} {$y <= ([$bb yMax] - 1) / $G} {incr y} { set M($x,$y) 1 } }
        continue
    }
    set k "[expr {([$bb xMin] + [$bb xMax]) / 2 / $G}],[expr {([$bb yMin] + [$bb yMax]) / 2 / $G}]"
    set A($k) [expr {[info exists A($k)] ? $A($k) + double([$m getWidth]) * [$m getHeight] : double([$m getWidth]) * [$m getHeight]}]
    incr N($k)
}
set l {}; set c70 0; set c85 0; set c95 0; set nb 0
foreach k [array names A] {
    if {[info exists M($k)]} continue
    incr nb; set ut [expr {$A($k) / double($G) / $G}]
    if {$ut > 0.70} { incr c70 }; if {$ut > 0.85} { incr c85 }; if {$ut > 0.95} { incr c95 }
    lassign [split $k ,] x y; lappend l [list [expr {$x * 50}] [expr {$y * 50}] $ut $N($k)]
}
puts "R39BINS free_bins_with_cells $nb util>0.70 $c70 >0.85 $c85 >0.95 $c95"
foreach e [lrange [lsort -real -decreasing -index 2 $l] 0 11] { puts [format "R39BIN x %d y %d util %.3f cells %d" {*}$e] }
