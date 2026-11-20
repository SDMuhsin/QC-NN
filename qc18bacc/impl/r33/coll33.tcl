# R33 A/B: collapse clumped repeater pairs (buffer b1 whose output net has a single load, a buffer b2 within R33_D um
# [10]: b1 is removed, its input net now drives b2) on a db; optional GRT with the production recipe; timing stats.
# env R33_DB, R33_ODBIN, R33_COLL (1 collapse), R33_GRT (1 global route + GRT parasitics), R33_TAG, QB_IO_LAT, QB9_W
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set _f [open $::OUT/config.tcl]; set _t [read $_f]; close $_f
eval [string map {r31_snap/ r31_snap4/} $_t]
qc_config
set step [qc_env R33_DB cts_rt]; set tag $::env(R33_TAG)
qc_read_liberty
read_db [qc_env R33_ODBIN $::OUT/db/$step.odb]
set_dont_use $::QC_PNR_DONT_USE
read_sdc $::OUT/db/$step.sdc
qc_set_rc
set_propagated_clock [all_clocks]
set L $::env(QB_IO_LAT); set per [get_property [get_clocks qb_clk] period]
source $::env(QB_IO_BUDGET); qb5_io_apply $per $L
proc isbuf {m} { return [regexp {^(BUFF|CKBD)} [$m getName]] }
proc pairs {} {
    set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]; set out {}
    foreach i [$blk getInsts] {
        set m [$i getMaster]; if {![isbuf $m]} continue
        set o [$i findITerm Z]; if {$o eq "NULL"} continue
        set n [$o getNet]; if {$n eq "NULL" || [$n getSigType] ne "SIGNAL" || [llength [$n getBTerms]]} continue
        set s {}; foreach it [$n getITerms] { if {[$it isInputSignal]} { lappend s $it } }
        if {[llength $s] != 1} continue
        set b2 [[lindex $s 0] getInst]; if {![isbuf [$b2 getMaster]]} continue
        lassign [$i getLocation] x1 y1; lassign [$b2 getLocation] x2 y2
        if {(abs($x1 - $x2) + abs($y1 - $y2)) / $u < [qc_env R33_D 10.0]} { lappend out $i }
    }
    return $out
}
proc stats {k} {
    set ws [expr {[sta::worst_slack_cmd max] * 1e9}]; set n [sta::endpoint_violation_count max]
    set io [concat [get_ports -quiet *] ]
    set pe [lindex [find_timing_paths -from [all_registers -clock_pins] -to [all_registers -data_pins] -path_delay max -group_count 1] 0]
    set r2 [format %.3f [expr {[$pe slack] * 1e9}]]
    set pb [lindex [find_timing_paths -to [get_pins u_top_g_ptr_b2_b2w_q_reg_0_/D] -path_delay max -group_count 1] 0]
    set b2 [format %.3f [expr {[$pb slack] * 1e9}]]
    set nv 0; set nb 0; set a 0.0; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    foreach i [[ord::get_db_block] getInsts] { set m [$i getMaster]; if {[$m isBlock]} continue; set a [expr {$a + [$m getWidth] * [$m getHeight]}]; if {[isbuf $m]} { incr nb } }
    puts [format "R33X %s %s wns %.3f viol %d reg2reg_wns %s b2w_q0 %s buffers %d std_um2 %.0f" $::env(R33_TAG) $k $ws $n $r2 $b2 $nb [expr {$a / $u / $u}]]
    flush stdout
}
estimate_parasitics -placement
stats loaded_pl
if {[qc_env R33_COLL 0]} {
    set tot 0
    for {set it 0} {$it < 6} {incr it} {
        set ps [pairs]; if {![llength $ps]} break
        set k 0
        foreach b1 $ps {
            set in [[$b1 findITerm I] getNet]; set o [[$b1 findITerm Z] getNet]
            if {$in eq "NULL" || $o eq "NULL"} continue
            set s {}; foreach x [$o getITerms] { if {[$x isInputSignal]} { lappend s $x } }
            if {[llength $s] != 1} continue
            set b2it [lindex $s 0]
            $b2it disconnect; [$b1 findITerm I] disconnect; [$b1 findITerm Z] disconnect
            $b2it connect $in
            odb::dbInst_destroy $b1
            if {[llength [$o getITerms]] == 0} { odb::dbNet_destroy $o }
            incr k
        }
        incr tot $k
        puts "R33X $tag collapse pass $it removed $k"
    }
    estimate_parasitics -placement
    stats collapsed_pl
}
if {[qc_env R33_GRT 0]} {
    set_routing_layers -signal M2-M9 -clock M2-M9
    set_global_routing_layer_adjustment M2-M9 0.25
    foreach {l a} {M5-M9 0.10 M2-M3 0.6} { set_global_routing_layer_adjustment $l $a }
    set t [clock seconds]
    global_route -congestion_iterations 10 -allow_congestion
    puts "R33X $tag global_route [expr {[clock seconds] - $t}] s"
    estimate_parasitics -global_routing
    stats grt
    if {[qc_env R33_GRTREP 0]} {
        global_route -start_incremental
        if {[qc_env R33_IOFP 1]} { set_false_path -from [all_inputs]; set_false_path -to [all_outputs] }
        set t [clock seconds]
        repair_timing -setup -setup_margin 0.0 -repair_tns [qc_env R33_TNS 100] -max_utilization 90
        puts "R33X $tag post-GRT repair_timing [expr {[clock seconds] - $t}] s"
        if {[qc_env R33_IOFP 1]} { unset_path_exceptions -from [all_inputs]; unset_path_exceptions -to [all_outputs] }
        detailed_placement -max_displacement 500
        global_route -end_incremental
        estimate_parasitics -global_routing
        stats grt_repaired
    }
    report_checks -path_delay max -to [get_pins u_top_g_ptr_b2_b2w_q_reg_0_/D] -fields {input_pins slew cap fanout} -digits 3 > /tmp/ckp908/qc18bacc/r33/coll33_${tag}_b2w.rpt
}
if {[qc_env R33_ODB ""] ne ""} { write_db $::env(R33_ODB) }
exit
