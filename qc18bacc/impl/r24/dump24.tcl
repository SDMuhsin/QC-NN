# R24 (results/r24.md): placement dumps for the legalisation-displacement diagnosis (disp24.py).
#   qb24_dump <file>      one line per std-cell instance: name master x y w h status (DBU, lower left)
#   qb24_geom <file>      M lines: macro bbox (DBU, without halo); B lines: placement blockages (bbox, max density, soft);
#                         C line: core area; U: DBU per um
proc qb24_dump {file} {
    set f [open $file w]
    foreach i [[ord::get_db_block] getInsts] {
        set m [$i getMaster]
        if {[$m isBlock]} { continue }
        set b [$i getBBox]
        puts $f "[$i getName] [$m getName] [$b xMin] [$b yMin] [$b getDX] [$b getDY] [$i getPlacementStatus]"
    }
    close $f
    qc_log "r24: dump $file"
}
proc qb24_geom {file} {
    set blk [ord::get_db_block]
    set f [open $file w]
    puts $f "U [[ord::get_db_tech] getDbUnitsPerMicron]"
    set c [$blk getCoreArea]
    puts $f "C [$c xMin] [$c yMin] [$c xMax] [$c yMax]"
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isBlock]} { continue }
        set b [$i getBBox]
        puts $f "M [$i getName] [$b xMin] [$b yMin] [$b xMax] [$b yMax]"
    }
    foreach k [$blk getBlockages] {
        set b [$k getBBox]
        puts $f "B [$b xMin] [$b yMin] [$b xMax] [$b yMax] [$k getMaxDensity] [$k isSoft]"
    }
    close $f
}
# hold violators by class (H3): start (port class / reg / macro / icg) x end (reg D / icg E / macro / port), with
# count, worst / mean slack (ns) -> file, one line per class
proc qb24_cls {file {delay min} {nmax 40000}} {
    if {[catch { qb24_cls_ $file $delay $nmax } e]} { qc_log "r24: qb24_cls $file failed: $e" }
}
proc qb24_cls_ {file delay nmax} {
    set ps [find_timing_paths -path_delay $delay -group_count $nmax -endpoint_count 1 -slack_max 0]
    array set n {}; array set w {}; array set sa {}
    foreach pe $ps {
        set k "[qb24_pin_cls [get_property $pe startpoint]]>[qb24_pin_cls [get_property $pe endpoint]]"
        set s [get_property $pe slack]
        if {![info exists n($k)]} { set n($k) 0; set w($k) 1e9; set sa($k) 0; set sr($k) 0 }
        incr n($k); if {$s < $w($k)} { set w($k) $s }
        set sa($k) [expr {$sa($k) + $s}]
    }
    set f [open $file w]
    foreach k [lsort [array names n]] {
        set sc [expr {abs($w($k)) < 1e-3 ? 1e9 : 1.0}]
        puts $f [format "%s %d worst %.3f mean %.3f" $k $n($k) [expr {$w($k) * $sc}] [expr {$sa($k) / $n($k) * $sc}]]
    }
    close $f
    qc_log "r24: $delay classes [llength $ps] paths -> $file"
}
# class of a path start / end point: port -> p:<name stem>; pin -> <master class>:<pin>
proc qb24_pin_cls {pt} {
    set nm [get_full_name $pt]
    if {[string first / $nm] < 0} { regsub {\[.*$} $nm {} s; regsub {_?[0-9]+$} $s {} s; return "p:$s" }
    set c [get_cells -of_objects $pt]; set ref [get_property $c ref_name]
    set pin [lindex [split $nm /] end]; regsub {\[.*$} $pin {} pin
    if {[string match qb_* $ref]} { return "$ref:$pin" }
    if {[string match CKLN* $ref]} { return "icg:$pin" }
    if {[regexp {^(DF|SDF|ED|LH|LN)} $ref]} { return "reg:$pin" }
    return "$ref:$pin"
}
