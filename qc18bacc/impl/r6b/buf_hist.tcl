# impl/r6b: where the DRV-repair buffers sit (QB_RUN, QB_DB default predpl): count / area per 100-um tile, top tiles,
# and per R6a group rectangle / over macros / no-row area.
read_db $::env(QB_RUN)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "predpl"}].odb
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
array set t {}; array set kind {}
set n 0
foreach i [$blk getInsts] {
    if {![regexp {^(wire|fanout|max_length|load_slew|max_cap|split|rebuffer)} [$i getName] -> k]} continue
    lassign [$i getLocation] x y
    set key "[expr {int($x / $u / 100)}],[expr {int($y / $u / 100)}]"
    if {[info exists t($key)]} { incr t($key) } else { set t($key) 1 }
    if {[info exists kind($k)]} { incr kind($k) } else { set kind($k) 1 }
    incr n
}
puts "BUF total $n kinds [array get kind] tiles [array size t]"
set l {}; foreach k [array names t] { lappend l [list $k $t($k)] }
foreach e [lrange [lsort -integer -decreasing -index 1 $l] 0 24] { puts "BUF tile_100um [lindex $e 0] n [lindex $e 1]" }
exit
