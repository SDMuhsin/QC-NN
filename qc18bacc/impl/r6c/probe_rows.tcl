# R6c probe (read-only) on a checkpoint QB_RUN/db/QB_DB.odb: row area / std-cell area per R6b group rectangle
# (mplace.tcl.groups), non-row core area, and the detour of repair buffers (wire* / max_length* / load_slew*):
# per buffer, d_in + d_out (driver -> buffer, buffer -> load centroid) vs driver -> load centroid (um).
set run $::env(QB_RUN); set db [expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "place"}]
read_db $run/db/$db.odb
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set core [$blk getCoreArea]
set ra 0.0; array set rg {}; array set cg {}; array set G {}
set f [open $run/mplace.tcl.groups]
while {[gets $f l] >= 0} { set w [split [string trim $l] " "]; set G([lindex $w 0]) [lrange $w 1 end]; set rg([lindex $w 0]) 0.0; set cg([lindex $w 0]) 0.0 }
close $f
proc grp_of {x y} {
    foreach g [array names ::G] { foreach {a b c d} $::G($g) { if {$x >= $a && $x < $c && $y >= $b && $y < $d} { return $g } } }
    return X
}
set rg(X) 0.0; set cg(X) 0.0
foreach r [$blk getRows] {
    set b [$r getBBox]; set a [expr {[$b dx] * double([$b dy]) / $u / $u}]
    set ra [expr {$ra + $a}]
    set g [grp_of [expr {([$b xMin] + [$b xMax]) / 2.0 / $u}] [expr {[$b yMin] / $u + 0.5}]]
    set rg($g) [expr {$rg($g) + $a}]
}
set ma 0.0; set sa 0.0
foreach i [$blk getInsts] {
    set m [$i getMaster]; set a [expr {[$m getWidth] * double([$m getHeight]) / $u / $u}]
    if {[$m isBlock]} { set ma [expr {$ma + $a}]; continue }
    set sa [expr {$sa + $a}]
    lassign [$i getLocation] x y
    set g [grp_of [expr {$x / $u}] [expr {$y / $u}]]
    set cg($g) [expr {$cg($g) + $a}]
}
set ca [expr {[$core dx] * double([$core dy]) / $u / $u}]
puts [format "ROWS db %s core_mm2 %.3f macro_mm2 %.3f row_mm2 %.3f nonrow_nonmacro_mm2 %.3f std_mm2 %.3f row_util %.3f" $db \
    [expr {$ca/1e6}] [expr {$ma/1e6}] [expr {$ra/1e6}] [expr {($ca-$ma-$ra)/1e6}] [expr {$sa/1e6}] [expr {$sa/$ra}]]
foreach g [lsort [array names rg]] { puts [format "ROWS_GRP %s row_mm2 %.3f std_mm2 %.3f util %.3f" $g [expr {$rg($g)/1e6}] [expr {$cg($g)/1e6}] [expr {$rg($g) > 0 ? $cg($g)/$rg($g) : 0}]] }
# repair buffer detour
array set h {}; set n 0; set ex 0.0; set dsum 0.0
foreach k {r1 r2 r3 r4 r5} { set h($k) 0 }
foreach i [$blk getInsts] {
    set nm [$i getName]
    if {![regexp {^(wire|max_length|load_slew|max_cap|fanout)\d+} $nm]} continue
    set in ""; set out ""
    foreach it [$i getITerms] { if {[$it getNet] eq "NULL" || [[$it getNet] getSigType] ne "SIGNAL"} continue; if {[$it isInputSignal]} { set in [$it getNet] } elseif {[$it isOutputSignal]} { set out [$it getNet] } }
    if {$in eq "" || $out eq ""} continue
    lassign [$i getLocation] bx by
    set dx ""; set dy ""
    foreach it [$in getITerms] { if {[$it isOutputSignal]} { lassign [[$it getInst] getLocation] dx dy } }
    if {$dx eq ""} { foreach bt [$in getBTerms] { lassign [$bt getFirstPinLocation] _ dx dy } }
    if {$dx eq ""} continue
    set lx 0.0; set ly 0.0; set nl 0
    foreach it [$out getITerms] { if {[$it isInputSignal]} { lassign [[$it getInst] getLocation] x y; set lx [expr {$lx + $x}]; set ly [expr {$ly + $y}]; incr nl } }
    if {$nl == 0} continue
    set lx [expr {$lx / $nl}]; set ly [expr {$ly / $nl}]
    set dir [expr {(abs($dx - $lx) + abs($dy - $ly)) / $u}]
    set via [expr {(abs($dx - $bx) + abs($dy - $by) + abs($bx - $lx) + abs($by - $ly)) / $u}]
    set e [expr {$via - $dir}]
    incr n; set ex [expr {$ex + $e}]
    if {$e < 20} { incr h(r1) } elseif {$e < 100} { incr h(r2) } elseif {$e < 300} { incr h(r3) } elseif {$e < 1000} { incr h(r4) } else { incr h(r5) }
}
puts [format "DETOUR db %s repair_bufs %d extra_um_sum %.0f mean %.1f hist <20 %d 20-100 %d 100-300 %d 300-1000 %d >1000 %d" $db $n $ex [expr {$ex / max(1,$n)}] $h(r1) $h(r2) $h(r3) $h(r4) $h(r5)]
