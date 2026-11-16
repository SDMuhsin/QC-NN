# R6c probe (read-only): for the cells listed in QB_FAIL (rpt/spread3_fail_<k>.txt: name master x y, before the
# fallback), on QB_RUN/db/QB_DB.odb: the original driver of the buffer tree (walking up through repair buffers),
# its hierarchy prefix (3 levels) and the load-centroid distance; histogram by prefix, with the mean pre-fallback
# location (um).
read_db $::env(QB_RUN)/db/$::env(QB_DB).odb
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
array set n {}; array set sx {}; array set sy {}; array set ex {}
set f [open $::env(QB_FAIL)]
while {[gets $f l] >= 0} {
    lassign $l nm ms x y
    set i [$blk findInst $nm]; if {$i eq "NULL"} continue
    set d $i; set hop 0
    while {$hop < 60} {
        set in ""; foreach it [$d getITerms] { if {[$it isInputSignal] && [$it getNet] ne "NULL"} { set in [$it getNet]; break } }
        if {$in eq ""} break
        set drv ""; foreach it [$in getITerms] { if {[$it isOutputSignal]} { set drv [$it getInst] } }
        if {$drv eq ""} { set drv "PORT"; break }
        set d $drv; incr hop
        if {![regexp {^(wire|max_length|load_slew|max_cap|fanout|split)\d+} [$d getName]]} break
    }
    if {$d eq "PORT"} { set k PORT } else {
        set k [join [lrange [split [$d getName] /] 0 2] /]
        regsub -all {_reg_[0-9_]+_?$|\d+_?$} $k {} k
        regsub -all {\[\d+\]} $k {} k
        if {[[$d getMaster] isBlock]} { set k "BLOCK:[[$d getMaster] getName]" }
    }
    if {![info exists n($k)]} { set n($k) 0; set sx($k) 0.0; set sy($k) 0.0; set ex($k) "" }
    incr n($k); set sx($k) [expr {$sx($k) + $x}]; set sy($k) [expr {$sy($k) + $y}]
    if {$ex($k) eq ""} { set ex($k) $nm }
}
close $f
set ks [lsort -command {apply {{a b} {expr {$::n($b) - $::n($a)}}}} [array names n]]
foreach k [lrange $ks 0 14] { puts [format "FAIL_SRC %6d %-50s mean_xy %.0f %.0f e.g. %s" $n($k) $k [expr {$sx($k)/$n($k)}] [expr {$sy($k)/$n($k)}] $ex($k)] }
