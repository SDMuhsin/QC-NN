# impl/r7a (read-only): per block / macro master, routing layers with obstructions and the obstructed area
# fraction of the master on each (box-area sum / master area, overlaps double counted).  QB_RUN, QB_DB, QB_OUT.
read_db $::env(QB_RUN)/db/$::env(QB_DB).odb
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set fo [open $::env(QB_OUT) w]; array set seen {}
foreach i [$blk getInsts] {
    set m [$i getMaster]; if {![$m isBlock] || [info exists seen([$m getName])]} continue
    set seen([$m getName]) 1; array unset a; array set a {}
    foreach b [$m getObstructions] {
        set l [$b getTechLayer]; if {$l eq "NULL"} continue
        set ln [$l getName]; if {![info exists a($ln)]} { set a($ln) 0.0 }
        set a($ln) [expr {$a($ln) + [$b getDX] * double([$b getDY])}]
    }
    set ma [expr {[$m getWidth] * double([$m getHeight])}]
    set s {}; foreach ln [lsort [array names a]] { lappend s "$ln=[format %.2f [expr {$a($ln) / $ma}]]" }
    puts $fo "O [$m getName] $s"
}
close $fo; exit
