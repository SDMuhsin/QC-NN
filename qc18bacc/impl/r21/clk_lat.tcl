# R21 clock latency distribution of a post-CTS checkpoint (QB_DB [cts]): propagated arrival at every register / macro clock
# pin (rise), split gated (behind a CKLNQD ICG) / ungated, quantiles -> R21_LAT lines; pt_blk-style L = (max + min) / 2.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env QB_DB cts]
set_propagated_clock [all_clocks]
estimate_parasitics -placement
set g {}; set u {}
set blk [ord::get_db_block]
# gated nets: nets reachable from an ICG output through clock buffers
array set GN {}
foreach i [$blk getInsts] {
    if {![string match CKLNQD* [[$i getMaster] getName]]} continue
    foreach it [$i getITerms] { if {[$it isOutputSignal] && [$it getNet] ne "NULL"} { set GN([[$it getNet] getName]) 1 } }
}
set ch 1
while {$ch} { set ch 0
    foreach i [$blk getInsts] {
        set m [[$i getMaster] getName]
        if {![string match CKB* $m] && ![string match BUFF* $m]} continue
        set in ""; set on ""
        foreach it [$i getITerms] { set n [$it getNet]; if {$n eq "NULL"} continue
            if {[$it isInputSignal]} { set in [$n getName] } elseif {[$it isOutputSignal]} { set on [$n getName] } }
        if {$in ne "" && $on ne "" && [info exists GN($in)] && ![info exists GN($on)]} { set GN($on) 1; set ch 1 }
    }
}
set probs [list arrival_max_rise max_rise_arrival]
foreach p [all_registers -clock_pins] {
    set a ""
    foreach pr $probs { if {![catch {get_property $p $pr} v] && $v ne ""} { set a $v; break } }
    if {$a eq "" || $a eq "INF" || $a eq "-INF"} continue
    if {$a < 1e-6} { set a [expr {$a * 1e9}] }
    set nn [get_full_name [get_nets -of_objects $p]]
    if {[info exists GN($nn)]} { lappend g $a } else { lappend u $a }
}
proc q {l} { set l [lsort -real $l]; set n [llength $l]; if {!$n} { return "n 0" }
    format "n %d min %.3f p10 %.3f p50 %.3f p90 %.3f max %.3f" $n [lindex $l 0] [lindex $l [expr {$n/10}]] [lindex $l [expr {$n/2}]] [lindex $l [expr {9*$n/10}]] [lindex $l end] }
puts "R21_LAT gated   [q $g]"
puts "R21_LAT ungated [q $u]"
set all [lsort -real [concat $g $u]]
puts [format "R21_LAT all L_mid %.3f (min %.3f max %.3f)" [expr {([lindex $all 0] + [lindex $all end]) / 2.0}] [lindex $all 0] [lindex $all end]]
exit
