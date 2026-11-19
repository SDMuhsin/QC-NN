# R27: std-cell area / instances / signal pins (+ buffer instances by master) of $QC_PNR_OUT/db/[QB_DB place].odb.
read_db $::env(QC_PNR_OUT)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "place"}].odb
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]; set a 0.0; set n 0; set p 0; array set BM {}; set ab 0.0
foreach i [[ord::get_db_block] getInsts] {
    set m [$i getMaster]; if {[$m isBlock]} continue
    set ar [expr {[$m getWidth] * [$m getHeight] / $u / $u}]; incr n; set a [expr {$a + $ar}]
    if {[regexp {^(BUFF|CKB)D} [$m getName]]} { incr BM([$m getName]); set ab [expr {$ab + $ar}] }
    foreach it [$i getITerms] { set nt [$it getNet]; if {$nt ne "NULL" && [$nt getSigType] eq "SIGNAL"} { incr p } }
}
puts [format "R27_ST std_um2 %.1f insts %d signal_pins %d buf_um2 %.1f" $a $n $p $ab]
puts "R27_STB [lrange [lsort -stride 2 -index 1 -integer -decreasing [array get BM]] 0 9]"
