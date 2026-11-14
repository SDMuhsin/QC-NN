# Per-bin standard-cell utilisation of a routed block (results/r5a.md): openroad -exit density.tcl with env
# QB5_DB (odb), QB5_OUT (text: x y util pe_frac per QB5_BIN-um bin, core area only).
read_db $::env(QB5_DB)
set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
set B [expr {[info exists ::env(QB5_BIN)] ? $::env(QB5_BIN) : 50.0}]
array set a {}; array set p {}
foreach i [$blk getInsts] {
    set m [$i getMaster]
    if {![$m isCore] || [$m getType] in {CORE_SPACER CORE_TIEHIGH CORE_TIELOW CORE_WELLTAP} || [regexp {^(FILL|DCAP|GFILL)} [$m getName]]} { continue }
    set bb [$i getBBox]
    set x [expr {([$bb xMin] + [$bb xMax]) / 2.0 / $u}]; set y [expr {([$bb yMin] + [$bb yMax]) / 2.0 / $u}]
    set k "[expr {int($x / $B)}] [expr {int($y / $B)}]"
    set ar [expr {[$bb getDX] * double([$bb getDY]) / $u / $u}]
    set a($k) [expr {[info exists a($k)] ? $a($k) + $ar : $ar}]
    if {[string match {u_core/g_r_*} [$i getName]]} { set p($k) [expr {[info exists p($k)] ? $p($k) + $ar : $ar}] }
}
set f [open $::env(QB5_OUT) w]
foreach k [array names a] {
    lassign $k bx by
    puts $f [format "%g %g %.3f %.3f" [expr {$bx * $B}] [expr {$by * $B}] [expr {$a($k) / $B / $B}] [expr {[info exists p($k)] ? $p($k) / $a($k) : 0}]]
}
close $f
puts "QB5_DENSITY done [array size a] bins"
