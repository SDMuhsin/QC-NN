# Top timing classes (results/r11.md; route/top_post_grt.tcl): worst setup slack per top-level path class (start -> end: hub / act / col / seq / mac / io / glue) from the
# worst 20000 endpoints; fmax_est = 1000 / (P - slack) (the block-side budgets are in the proxy liberty /
# ETM arcs).  Writes rpt/classes_tt.txt + summary lines.
proc qb11_cls {pin} {
    if {[catch {set o [get_property $pin full_name]}]} { set o $pin }
    if {[string match u_hub/* $o]} { return hub }
    if {[string match u_act_blk/* $o]} { return act }
    if {[string match *u_col/* $o]} { return col }
    if {[string match *u_seq* $o]} { return seq }
    if {[string first / $o] < 0} { return io }
    set i [string range $o 0 [expr {[string last / $o] - 1}]]
    set m [get_property [get_cells $i] ref_name]
    if {[string match qb_w* $m] || [string match qb_d* $m]} { return mac }
    return glue
}
proc qb11_classes {{corner tt}} {
    set per [get_property [get_clocks qb_clk] period]
    set ps [find_timing_paths -path_delay max -group_count 20000 -endpoint_count 1 -sort_by_slack]
    array set w {}; array set n {}; array set ex {}
    foreach p $ps {
        set s [get_property $p slack]
        set k "[qb11_cls [get_property $p startpoint]]->[qb11_cls [get_property $p endpoint]]"
        incr n($k)
        if {![info exists w($k)] || $s < $w($k)} { set w($k) $s; set ex($k) "[get_full_name [get_property $p startpoint]] -> [get_full_name [get_property $p endpoint]]" }
    }
    set f [open $::OUT/rpt/classes_$corner.txt w]
    puts $f "# R11 top classes ($corner, period $per ns, worst [llength $ps] endpoints): class n_ep worst_slack_ns fmax_est_MHz example"
    foreach k [lsort [array names w]] {
        set s [expr {$w($k) * ([string is double $w($k)] && abs($w($k)) > 1e-3 ? 1.0 : 1e9)}]
        set l [format "%-14s %6d %8.3f %7.1f  %s" $k $n($k) $s [expr {1000.0 / ($per - $s)}] $ex($k)]
        puts $f $l; qc_summary "r11 class $corner $l"
    }
    close $f
}
qb11_classes tt
