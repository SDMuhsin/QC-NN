# Top clock measurement (results/r14.md, r43.md; sourced by cts/top_balance.tcl and route/top_post_grt.tcl): effective clock arrival per sink group =
# clock arrival at the pin (propagated, current parasitics) + the block's internal insertion (column QB11_INS, hub
# QB14_HINS, act QB14_AINS: each block's own measured tt p50, blocks/top/run.sh from the views' ins_tt.txt; top flops 0).  Groups: col0..7, hub, act, top flops by region
# (gap / nw / n0..n3 as cts/top_clock_tree.tcl; 250 flops sampled per group).  q14_report <file> writes the table +
# the global effective skew (max - min over every sampled sink); without a file it only fills ::Q14_EFF (median).
proc q14_arr {name} {
    set p [get_pins -quiet $name]
    if {$p eq ""} { return "" }
    set best ""
    # R43 (results/r43.md): the rising-edge arrival of qb_clk (max over the APs).  (R14 took
    # vertex_worst_arrival_path = the latest arrival over BOTH clock edges, i.e. the falling-edge arrival latency + P/2:
    # every clk14 number, and the top IO latency 7.7 copied from it, was P/2 = 3.25 ns too large.)
    set clk [lindex [get_clocks qb_clk] 0]
    foreach v [$p vertices] {
        if {$v eq "NULL"} { continue }
        foreach a [$v arrivals_clk rise $clk rise] { if {$a < 1e-3 && $a > -1e-3 && ($best eq "" || $a * 1e9 > $best)} { set best [expr {$a * 1e9}] } }
    }
    return $best
}
proc q14_groups {} {
    if {![info exists ::Q14_GATED] && [file exists $::OUT/rpt/q14_gated.txt]} {
        set f [open $::OUT/rpt/q14_gated.txt]; while {[gets $f l] >= 0} { set ::Q14_GATED([lindex $l 0]) [lindex $l 1] }; close $f
    }
    if {![info exists ::Q14_GATED]} { array set ::Q14_GATED {} }
    set b [ord::get_db_block]; set u [$b getDefUnits]
    lassign $::QB11_ACT ax1 ay1 ax2 ay2
    array set g {}; array set cnt {}
    set ns 250
    foreach i [$b getInsts] {
        set m [[$i getMaster] getName]
        if {$m eq "qb_hub"} { set g(hub) [list [list [$i getName]/clk $::env(QB14_HINS)]]; continue }
        if {$m eq "qb_act2_blk"} { set g(act) [list [list [$i getName]/clk $::env(QB14_AINS)]]; continue }
        if {$m eq "qb_col_blk"} { regexp {g_c_(\d+)_} [$i getName] -> c; set g(col$c) [list [list [$i getName]/clk $::env(QB11_INS)]]; continue }
        if {[string match CKLN* $m] || [$i findITerm CP] eq "NULL"} { continue }
        set bb [$i getBBox]; set x [expr {([$bb xMin] + [$bb xMax]) / 2.0 / $u}]; set y [expr {([$bb yMin] + [$bb yMax]) / 2.0 / $u}]
        if {$x < $::QB14_X0 && $y < $ay1} { set k gap } elseif {$x < $::QB14_X0} { set k nw } else { set k n[expr {min(3, int(($x - $::QB14_X0) / 780.0))}] }
        if {[info exists ::Q14_GATED([$i getName])]} { set k $::Q14_GATED([$i getName]) }
        lappend g($k) [list [$i getName]/CP 0.0]
    }
    foreach k [array names g] {
        set n [llength $g($k)]
        if {$n > $ns} { set s {}; for {set j 0} {$j < $ns} {incr j} { lappend s [lindex $g($k) [expr {int($j * double($n) / $ns)}]] }; set g($k) $s }
    }
    return [array get g]
}
proc q14_measure {} {
    report_worst_slack -max
    array set g [q14_groups]
    array set ::Q14_EFF {}; array set ::Q14_STAT {}
    foreach k [lsort [array names g]] {
        set l {}
        foreach e $g($k) { set a [q14_arr [lindex $e 0]]; if {$a ne ""} { lappend l [expr {$a + [lindex $e 1]}] } }
        if {![llength $l]} { continue }
        set l [lsort -real $l]
        set ::Q14_EFF($k) [lindex $l [expr {[llength $l] / 2}]]
        set ::Q14_STAT($k) [list [llength $l] [lindex $l 0] [lindex $l [expr {[llength $l] / 2}]] [lindex $l end]]
    }
}
proc q14_report {file {tag ""}} {
    q14_measure
    set f [open $file a]
    puts $f "# R14 clock $tag: effective arrival (pin arrival + block insertion), ns tt: group n min median max"
    set mn 1e9; set mx -1e9
    foreach k [lsort [array names ::Q14_STAT]] {
        lassign $::Q14_STAT($k) n a b c
        puts $f [format "%-6s %5d %7.3f %7.3f %7.3f" $k $n $a $b $c]
        set mn [expr {min($mn, $a)}]; set mx [expr {max($mx, $c)}]
    }
    set med {}; foreach k [array names ::Q14_EFF] { lappend med $::Q14_EFF($k) }
    set med [lsort -real $med]
    puts $f [format "global effective skew (all sampled sinks) %.3f ns; spread of group medians %.3f ns" [expr {$mx - $mn}] [expr {[lindex $med end] - [lindex $med 0]}]]
    close $f
    qc_log [format "r14 clock %s: global effective skew %.3f, group-median spread %.3f ns" $tag [expr {$mx - $mn}] [expr {[lindex $med end] - [lindex $med 0]}]]
}
