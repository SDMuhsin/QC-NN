# PRE_ROUTE_TCL of slice.cfg (results/pnr_slice.md): post-CTS timing repair at tt with placement parasitics, done
# here instead of in the flow's cts step (P(REPAIR_TIMING) 0) so that db/cts.odb holds the un-repaired clock tree
# and the repair can be re-run / diagnosed from it:
#   1. reports before repair (skew, worst setup with input pins, worst hold paths, violating endpoint counts)
#   2. repair_timing -setup (margin 0, QB_TNS % of the violating endpoints, default 100)
#   3. repair_timing -hold (margin P(HOLD_MARGIN)), at most QB_HOLD_PCT % new buffers (default 10)
#   4. detailed placement, reports, checkpoint db/cts_rt.odb
proc qb_counts {tag} {
    set s [sta::worst_slack_corner [sta::find_corner tt] max]; set h [sta::worst_slack_corner [sta::find_corner tt] min]
    set ns NA; set nh NA
    catch { set ns [sta::endpoint_violation_count max] }
    catch { set nh [sta::endpoint_violation_count min] }
    qc_summary [format "%s tt setup_wns_ns %.3f setup_viol_endpoints %s hold_wns_ns %.3f hold_viol_endpoints %s %s" $tag \
        [expr {$s * 1e9}] $ns [expr {$h * 1e9}] $nh [qc_util]]
}
estimate_parasitics -placement
# IO delays relative to the propagated clock: the DC SDC gives 20 % of the period relative to the ideal edge, so after
# CTS every input -> register path is a hold violation of ~ the insertion delay (qcs_w1: 8 016 hold endpoints, worst
# pf -> parameter bank -0.649 ns, latency 0.73 - 1.06 ns) and every register -> output path loses that latency in
# setup.  The neighbours of the slice (S macros, activation supply, parameter store) sit on the same clock tree, so
# the IO delays are shifted by QB_IO_LAT (default 0.85 ns, the mid insertion delay of this tree): input + L, output - L.
set L [qb_env QB_IO_LAT 0.85]
set per [get_property [get_clocks qb_clk] period]
set io_d [expr {0.2 * $per}]
set ins {}; set outs {}
foreach b [[ord::get_db_block] getBTerms] {
    set n [$b getName]
    if {$n in {clk rst_n} || [$b getSigType] ne "SIGNAL"} { continue }
    if {[$b getIoType] eq "INPUT"} { lappend ins $n } elseif {[$b getIoType] eq "OUTPUT"} { lappend outs $n }
}
set_input_delay [expr {$io_d + $L}] -clock qb_clk [get_ports $ins]
set_output_delay [expr {$io_d - $L}] -clock qb_clk [get_ports $outs]
qc_log "post_cts: IO delays shifted by $L ns ([llength $ins] inputs, [llength $outs] outputs)"
qc_to $::OUT/rpt/pc0_skew.rpt { report_clock_skew -setup; report_clock_skew -hold }
qc_to $::OUT/rpt/pc0_setup.rpt { report_checks -path_delay max -format full_clock_expanded -fields {input_pins slew cap fanout} -digits 3 }
qc_to $::OUT/rpt/pc0_hold.rpt { report_checks -path_delay min -format full_clock_expanded -group_count 5 -endpoint_count 1 -fields {input_pins} -digits 3 }
qb_counts postcts_pre_repair
# QB_RTSEQ 2 (results/pnr_slice2.md): every repair is followed by legalisation + parasitics re-estimate and a
# count line, so the setup lost to legalisation is measured per step; after the hold repair the setup repair is re-run
# (QB_RT_LOOPS rounds, default 2) and the hold repair only where hold violations reappear.  QB_RTSEQ 1 = pnr_slice.md.
proc qb_legal {tag} {
    detailed_placement {*}[p DPL_ARGS]
    estimate_parasitics -placement
    qb_counts $tag
}
proc qb_setup {} {
    set t [clock seconds]
    repair_timing -setup -setup_margin [qb_env QB_SETUP_MARGIN 0.0] -repair_tns [qb_env QB_TNS 100] -max_utilization [p MAX_UTIL]
    qc_log "repair_timing -setup [expr {[clock seconds] - $t}] s"
}
proc qb_hold {} {
    set t [clock seconds]
    if {[catch { repair_timing -hold -hold_margin [p HOLD_MARGIN] -max_buffer_percent [qb_env QB_HOLD_PCT 10] \
            -max_utilization [p MAX_UTIL] } e]} { qc_log "repair_timing -hold stopped: $e" }
    qc_log "repair_timing -hold [expr {[clock seconds] - $t}] s"
}
if {[qb_env QB_RTSEQ 2] == 2} {
    qb_setup
    qb_counts postcts_setup_repair
    qb_legal postcts_setup_legal
    qb_hold
    qb_counts postcts_hold_repair_unlegal
    qb_legal postcts_hold_legal
    for {set k 1} {$k <= [qb_env QB_RT_LOOPS 2]} {incr k} {
        qb_setup
        qb_counts postcts_setup${k}_repair
        qb_legal postcts_setup${k}_legal
        set nh 0; catch { set nh [sta::endpoint_violation_count min] }
        if {$nh > 0} { qb_hold; qb_legal postcts_hold${k}_legal }
    }
    check_placement
} else {
    set t [clock seconds]
    repair_timing -setup -setup_margin 0.0 -repair_tns [qb_env QB_TNS 100] -max_utilization [p MAX_UTIL]
    qc_log "repair_timing -setup [expr {[clock seconds] - $t}] s"
    qb_counts postcts_setup_repair
    set t [clock seconds]
    if {[catch { repair_timing -hold -hold_margin [p HOLD_MARGIN] -max_buffer_percent [qb_env QB_HOLD_PCT 10] \
            -max_utilization [p MAX_UTIL] } e]} { qc_log "repair_timing -hold stopped: $e" }
    qc_log "repair_timing -hold [expr {[clock seconds] - $t}] s"
    detailed_placement {*}[p DPL_ARGS]
    check_placement
    estimate_parasitics -placement
    qb_counts postcts_hold_repair
    # QB_RT2 1 (default): a second setup repair after legalisation (qcs_t1: -0.267 ns after the setup repair, -0.526 after
    # the hold repair + detailed placement moved the resized cells), then legalisation and the hold check again
    if {[qb_env QB_RT2 1]} {
        set t [clock seconds]
        repair_timing -setup -setup_margin 0.0 -repair_tns [qb_env QB_TNS 100] -max_utilization [p MAX_UTIL]
        detailed_placement {*}[p DPL_ARGS]
        estimate_parasitics -placement
        if {[catch { repair_timing -hold -hold_margin [p HOLD_MARGIN] -max_buffer_percent [qb_env QB_HOLD_PCT 10] \
                -max_utilization [p MAX_UTIL] } e]} { qc_log "repair_timing -hold (2) stopped: $e" }
        detailed_placement {*}[p DPL_ARGS]
        check_placement
        estimate_parasitics -placement
        qc_log "second setup repair [expr {[clock seconds] - $t}] s"
        qb_counts postcts_repair2
    }
}
qc_to $::OUT/rpt/pc1_setup.rpt { report_checks -path_delay max -format full_clock_expanded -fields {input_pins slew cap fanout} -digits 3 }
qc_to $::OUT/rpt/pc1_hold.rpt { report_checks -path_delay min -format full_clock_expanded -group_count 5 -endpoint_count 1 -fields {input_pins} -digits 3 }
write_db $::OUT/db/cts_rt.odb
