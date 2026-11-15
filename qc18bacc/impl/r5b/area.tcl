# impl/r5b: die-area breakdown of a chip checkpoint (QB_RUN, QB_DB step, default route_dr): die, column blocks, ARM
# macros, macro halos (keep-out), top standard cells (excluding fill / tap / decap), fill + decap, white space.
read_db $::env(QB_RUN)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "route_dr"}].odb
set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
set die [$blk getDieArea]
set dA [expr {[$die dx] / double($u) * [$die dy] / double($u)}]
array set a {blk 0 mac 0 std 0 fill 0 buf 0}
array set n {blk 0 mac 0 std 0 fill 0 buf 0}
foreach i [$blk getInsts] {
    set m [$i getMaster]; set ar [expr {[$m getWidth] / double($u) * [$m getHeight] / double($u)}]
    set mn [$m getName]
    if {$mn eq "qb_col_blk"} { set k blk } elseif {[$m isBlock]} { set k mac
    } elseif {[regexp {^(FILL|DCAP)} $mn]} { set k fill } else { set k std
        if {[regexp {^(BUFF|CKBD|INVD|CKND|DEL)} $mn]} { set a(buf) [expr {$a(buf) + $ar}]; incr n(buf) } }
    set a($k) [expr {$a($k) + $ar}]; incr n($k)
}
set rows 0.0
foreach r [$blk getRows] { set b [$r getBBox]; set rows [expr {$rows + [$b dx] / double($u) * [$b dy] / double($u)}] }
puts [format "AREA die_mm2 %.3f (%.1f x %.1f um)" [expr {$dA / 1e6}] [expr {[$die dx] / double($u)}] [expr {[$die dy] / double($u)}]]
foreach k {blk mac std fill} { puts [format "AREA %s_mm2 %.3f share %.3f n %d" $k [expr {$a($k) / 1e6}] [expr {$a($k) / $dA}] $n($k)] }
puts [format "AREA std_buf_inv_mm2 %.3f n %d" [expr {$a(buf) / 1e6}] $n(buf)]
puts [format "AREA row_area_mm2 %.3f std_util_in_rows %.3f" [expr {$rows / 1e6}] [expr {$a(std) / $rows}]]
puts [format "AREA other_mm2 %.3f share %.3f (halos, channels without rows, white space incl. empty rows)" \
    [expr {($dA - $a(blk) - $a(mac) - $a(std)) / 1e6}] [expr {($dA - $a(blk) - $a(mac) - $a(std)) / $dA}]]
exit
