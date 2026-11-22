# Clock insertion delay L of a design measured on its own clock tree (fix of the hard-coded L constants, R48): p50 of the
# rise arrival at every register / macro clock pin at the current parasitics (propagated clock), tt (OpenROAD times tt
# only; the PrimeTime sign-off measures every corner itself, signoff/pt/common.tcl qb_pt_lat).  qb_clk_lat <tag> sets
# QB_IO_LAT (the IO-budget shift of repair/post_cts.tcl, route/hub_post_grt.tcl, repair/hold_eco.tcl) and appends
# "<tag> tt <L>" to <run>/clk_lat.txt.
proc qb_clk_lat {tag} {
    set a {}
    foreach p [all_registers -clock_pins] {
        set v ""
        foreach pr {arrival_max_rise max_rise_arrival} { if {![catch {get_property $p $pr} x] && $x ne ""} { set v $x; break } }
        if {$v eq "" || $v eq "INF" || $v eq "-INF"} continue
        if {$v < 1e-6} { set v [expr {$v * 1e9}] }
        lappend a $v
    }
    set a [lsort -real $a]; set n [llength $a]
    if {$n == 0} { error "qb_clk_lat $tag: no clocked register pins" }
    set L [format %.3f [lindex $a [expr {$n / 2}]]]
    set ::env(QB_IO_LAT) $L
    set f [open $::OUT/clk_lat.txt a]; puts $f "$tag tt $L"; close $f
    qc_log [format "clk_lat %s: L %s (p50 of %d clock pins; p10 %.3f p90 %.3f min %.3f max %.3f)" $tag $L $n \
        [lindex $a [expr {$n / 10}]] [lindex $a [expr {9 * $n / 10}]] [lindex $a 0] [lindex $a end]]
    return $L
}
