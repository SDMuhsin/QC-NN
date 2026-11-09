# Diagnostic (not part of the flow): clock tree, hold and setup statistics of a P&R checkpoint, OpenROAD.
#   QC_FLOW=<repo>/flow/tsmc65 QC_PNR_OUT=<P&R run dir> QA_STEP=cts openroad -exit diag_cts.tcl > diag_<step>.txt
# Clock tree: cells named clkbuf* / clkload* (TritonCTS) by master, area; report_power (OpenROAD default activity:
# the clock nets toggle every edge, so the Clock group is meaningful; the data activity is the 0.1 default).
# Hold / setup: violating endpoints at ss and tt (placement / global-route parasitics as the step left them),
# grouped by start (input port / register / macro) and end kind (register, macro pin, ICG, output port), with the
# worst slack (ns) and endpoint of each group.  QA_STEP=grt: db/grt.odb of grt_only.tcl (global-route parasitics).
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts grt route finish}
set step [qc_env QA_STEP cts]
qc_load $step
if {$step in {route grt}} { estimate_parasitics -global_routing } else { estimate_parasitics -placement }
set blk [ord::get_db_block]
array set nm {}; array set ar {}; set ncts 0; set acts 0.0; set ctsl {}
foreach i [$blk getInsts] {
    set n [$i getName]
    if {[string match clkbuf* $n] || [string match clkload* $n]} {
        set m [[$i getMaster] getName]
        incr nm($m)
        set a [expr {[[$i getMaster] getWidth] * [[$i getMaster] getHeight] / 1e6}]
        set ar($m) [expr {[info exists ar($m)] ? $ar($m) + $a : $a}]
        incr ncts; set acts [expr {$acts + $a}]; lappend ctsl $n
    }
}
puts "DIAG step $step clock_tree_cells $ncts area_um2 [format %.0f $acts]"
foreach m [lsort [array names nm]] { puts "DIAG   $m n $nm($m) area_um2 [format %.0f $ar($m)]" }
puts "DIAG power_tt whole design (default activity; group Clock = clock-tree buffers + ICGs):"
report_power -corner tt
report_clock_skew
proc kind {pin} {
    if {[$pin is_top_level_port]} { return port }
    set cn [get_name [[$pin instance] cell]]
    if {[string match qa_* $cn]} { return macro }
    if {[string match CKLNQD* $cn]} { return icg }
    return reg
}
foreach c {ss tt} {
    foreach dt {min max} {
        set pes [find_timing_paths -path_delay $dt -corner $c -group_count 200000 -endpoint_count 1 -slack_max 0.0]
        array unset k; set worst 0.0
        foreach pe $pes {
            set pr [$pe path]
            set ps [$pr pins]
            set ep [$pr pin]
            set sp [lindex $ps 0]
            if {$sp eq $ep} { set sp [lindex $ps end] }
            set s [kind $sp]
            set e [kind $ep]
            incr k($s->$e)
            set sl [$pe slack]
            if {![info exists w($s->$e)] || $sl < $w($s->$e)} { set w($s->$e) $sl; set wp($s->$e) [get_full_name $ep] }
        }
        set str {}; foreach x [lsort [array names k]] { lappend str "$x $k($x) wns [format %.3f [expr {$w($x) * 1e9}]] ($wp($x))" }
        array unset w; array unset wp
        puts "DIAG $c [expr {$dt eq "min" ? "hold" : "setup"}] violating_endpoints [llength $pes] [join $str {, }]"
    }
}
puts "DIAG wall_s [expr {[clock seconds] - $::T0}]"
