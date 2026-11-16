# impl/r8 read-only probe (run.sh probe): where does the west-strip vertical routing demand come from?
# On db/$QB_DB.odb: every signal net -> class '<driver unit> -> <sink units>' (units: act = u_top/u_act, dist =
# u_top/g_dist_*, seq, prm, head, glue = other u_top std cells, chip = other top std cells, blk.<bus> = column-block pin,
# mac.<type> = macro pin, port); rsz repair buffers / CTS buffers keep their own name -> unit 'buf' (both ends of a
# buffered net are then 'buf'; the buffer trees are summarised separately by region).
# Per class: nets, HPWL dx / dy (m), and the part of the vertical extent inside the west strip x < QB8_XW (860)
# (dy of nets whose bbox overlaps the strip) -> V demand estimate; + y histogram (200 um) of act / dist / seq cells and
# of the column act pins actually connected.  Output QB_OUT [<run>/rpt/probe_west.txt].
set ::OUT $::env(QB_RUN)
read_db $::OUT/db/$::env(QB_DB).odb
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set XW [expr {[expr {[info exists ::env(QB8_XW)] ? $::env(QB8_XW) : 860.0}] * $u}]
proc unit {it} {
    set i [$it getInst]; set n [$i getName]; set m [$i getMaster]
    if {[$m isBlock]} {
        if {[regexp {g_c_\d+__u_col} $n]} { regexp {^([a-z_0-9]+)} [[$it getMTerm] getName] -> b; return "blk.$b" }
        if {[regexp {g_mac_g_([a-z0-9]+)_u_mac} $n -> t]} { return "mac.$t" }
        return mac
    }
    foreach {p k} {u_top/u_act/ act u_top/g_dist_ dist g_rt_u_seq/ seq u_prm/ prm u_head/ head} { if {[string first $p $n] >= 0} { return $k } }
    if {[regexp {^(wire|fanout|split|rebuffer|load_slew|max_cap|max_length|clkbuf|delay|hold)} $n]} { return buf }
    if {[string match u_top/* $n]} { return glue }
    return chip
}
array set C {}; array set Y {}
foreach net [$blk getNets] {
    if {[$net getSigType] ne "SIGNAL"} continue
    set d -; set s {}; set x0 1e18; set y0 1e18; set x1 -1e18; set y1 -1e18; set np 0
    foreach it [$net getITerms] {
        set k [unit $it]
        if {[$it isOutputSignal]} { set d $k } else { lappend s $k }
        set i [$it getInst]
        if {[[$i getMaster] isBlock]} { set b [$it getBBox] } else { set b [$i getBBox] }
        set x [expr {([$b xMin] + [$b xMax]) / 2}]; set y [expr {([$b yMin] + [$b yMax]) / 2}]
        set x0 [expr {min($x0, $x)}]; set x1 [expr {max($x1, $x)}]; set y0 [expr {min($y0, $y)}]; set y1 [expr {max($y1, $y)}]
        incr np
        if {$k eq "blk.act"} { set yb [expr {int($y / $u / 200)}]; if {[info exists Y(pin,$yb)]} { incr Y(pin,$yb) } else { set Y(pin,$yb) 1 } }
    }
    foreach bt [$net getBTerms] { if {[$bt getIoType] eq "INPUT"} { set d port } else { lappend s port } }
    if {$np < 2} continue
    set sk [join [lsort -unique $s] ,]
    set cl "$d -> $sk"
    set dx [expr {($x1 - $x0) / $u}]; set dy [expr {($y1 - $y0) / $u}]
    set dyw [expr {$x0 < $XW ? $dy : 0.0}]
    set dxw [expr {$x0 < $XW ? (min($x1, $XW) - $x0) / $u : 0.0}]
    if {![info exists C($cl)]} { set C($cl) {0 0.0 0.0 0.0 0.0} }
    lassign $C($cl) n a b c e
    set C($cl) [list [incr n] [expr {$a + $dx}] [expr {$b + $dy}] [expr {$c + $dyw}] [expr {$e + $dxw}]]
}
foreach i [$blk getInsts] {
    if {[[$i getMaster] isBlock]} continue
    set n [$i getName]; set k ""
    foreach {p kk} {u_top/u_act/ act u_top/g_dist_ dist g_rt_u_seq/ seq} { if {[string first $p $n] >= 0} { set k $kk; break } }
    if {$k eq ""} continue
    lassign [$i getLocation] x y
    set yb [expr {int($y / $u / 200)}]; set xw [expr {$x < $XW ? "w" : "e"}]
    set key "$k$xw,$yb"
    if {[info exists Y($key)]} { incr Y($key) } else { set Y($key) 1 }
}
set fo [open [expr {[info exists ::env(QB_OUT)] ? $::env(QB_OUT) : "$::OUT/rpt/probe_west.txt"}] w]
puts $fo "# probe_west $::env(QB_DB): class nets HPWL_dx_m HPWL_dy_m dy_westbbox_m dx_westbbox_m (sorted by dy_west)"
set rows {}
foreach cl [array names C] { lappend rows [concat [list $cl] $C($cl)] }
set tw 0.0; foreach r $rows { set tw [expr {$tw + [lindex $r 4]}] }
puts $fo [format "total dy_west %.2f m" [expr {$tw / 1e6}]]
foreach r [lrange [lsort -real -decreasing -index 4 $rows] 0 39] {
    lassign $r cl n a b c e
    puts $fo [format "%-60s %7d %8.3f %8.3f %8.3f %8.3f" [string range $cl 0 59] $n [expr {$a / 1e6}] [expr {$b / 1e6}] [expr {$c / 1e6}] [expr {$e / 1e6}]]
}
puts $fo "# y histogram (200-um bins, chip y): cells act/dist/seq west (x < XW) | east, connected column act pins"
for {set yb 0} {$yb < 30} {incr yb} {
    set l [format "y %4d-%4d" [expr {$yb * 200}] [expr {$yb * 200 + 200}]]
    foreach k {actw acte distw diste seqw seqe pin} { append l [format " %s %6d" $k [expr {[info exists Y($k,$yb)] ? $Y($k,$yb) : 0}]] }
    puts $fo $l
}
close $fo
puts "PROBE_WEST done"
