# Post-CTS and post-global-route timing of a core.cfg run at OpenROAD's parasitic estimates (stop-rule numbers of
# results/pnr_core.md), from db/cts.odb:  QC_FLOW=<repo>/flow/tsmc65 QC_PNR_OUT=<run> openroad -exit grt_est.tcl
#   QB_DRV_POST 1 (default): DRV repair + legalisation first (see below)
#   QB_GRT 1 (default): global route (route.tcl settings, no repair), estimate_parasitics -global_routing, db/grt.odb
# Reports rpt/est_<stage>_<corner>_{r2r,all,hold}.rpt (reg2reg = register clock pins -> register data pins, IO
# excluded; -fields input_pins, so wire delays are separate rows for wire_share.py) and summary lines est_<stage>.
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 8]
set ::STEPS {init floorplan pdn place cts route finish}
# restart from db/cts_drv.odb (DRV-repaired, legalised post-CTS placement of an earlier run) when it exists
if {[file exists $::OUT/db/cts_drv.odb]} { qc_load cts_drv; set_propagated_clock [all_clocks] } else { qc_load cts }
# reg2reg: the IO delays are removed after the "all" report (report_checks -from / -to [all_registers] on the
# 1.8 M-instance design segfaults in this build's STA: VertexIdLess set insert), so the worst constrained path is then
# between registers (incl. clock-gate enables)
proc qb_rep {stage} {
    set c tt
    set f $::OUT/rpt/est_${stage}_$c
    if {![info exists ::qb_io_off]} {
        qc_to $f.all.rpt { report_checks -corner $c -path_delay max -format full_clock_expanded -fields {input_pins} -digits 3 }
        qc_summary "est_$stage [join [qc_timing_lines est_$stage] { | }]"
        unset_input_delay -clock [get_clocks qb_clk] [all_inputs]
        unset_output_delay -clock [get_clocks qb_clk] [all_outputs]
        set ::qb_io_off 1
    }
    qc_to $f.r2r.rpt { report_checks -corner $c -path_delay max -format full_clock_expanded \
                           -fields {input_pins slew cap fanout} -digits 3 }
    qc_to $f.hold.rpt { report_checks -corner $c -path_delay min -format full_clock_expanded -digits 3 }
    # worst endpoint per block class (from the 3 000 worst endpoints), full path with input pins (wire_share.py)
    qc_to $f.ends.rpt { report_checks -corner $c -path_delay max -group_count 3000 -endpoint_count 1 -format end }
    set fh [open $f.ends.rpt]; set ends [read $fh]; close $fh
    foreach {cls re} {pe {u_pe/} lane_f {u_lf/} lane_w {u_lw/} bcast_dec {u_(br|dec)} pbank {u_pb} creg {cdr_reg|ctlr_reg}} {
        foreach line [split $ends \n] {
            if {[llength $line] >= 4 && [regexp $re [lindex $line 0]] && [regexp {(-?[0-9]+\.[0-9]+)\s*(\(VIOLATED\))?\s*$} $line -> sl]} {
                qc_to $f.cls_$cls.rpt { report_checks -corner $c -path_delay max -to [get_pins [lindex $line 0]] \
                    -format full_clock_expanded -fields {input_pins slew cap fanout} -digits 3 }
                qc_log "est_$stage class $cls worst endpoint [lindex $line 0] slack $sl"
                break
            }
        }
    }
    qc_to $::OUT/rpt/est_${stage}.skew.rpt { report_clock_skew }
    qc_summary "est_$stage [qc_util]"
    qc_summary "est_${stage}_r2r [join [qc_timing_lines est_${stage}_r2r] { | }]"
}
estimate_parasitics -placement
# QB_DRV_POST 1 (default): DRV repair of the violating nets after CTS legalisation, then legalisation (the v3
# P(QA_DRV_POST) lesson of qc18acc/pnr/post_cts.tcl): qbc_p1 place tt -5.25 ns on a wide lane whose D0 / D1 drivers
# see 0.03-0.04 pF after legalisation (0.5-0.7 ns slews), nets that were not violating when the place step repaired
if {[qc_env QB_DRV_POST 1] && ![file exists $::OUT/db/cts_drv.odb]} {
    qc_repair_drv
    # default window: DPL-0036 on qbc_p1 (utilisation 0.85 after CTS); the 300-um window of the v4 recipe
    detailed_placement -max_displacement {300 300}
    estimate_parasitics -placement
    write_db $::OUT/db/cts_drv.odb
    write_sdc $::OUT/db/cts_drv.sdc
}
qb_rep cts
if {[qc_env QB_GRT 1]} {
    set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
    set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
    # QB_GRT_ARGS (results/pnr_pe.md): extra global_route options, e.g. -allow_congestion (estimates despite GRT-0119)
    global_route -guide_file $::OUT/route_est.guide -congestion_iterations [p GR_ITER] \
        -congestion_report_file $::OUT/rpt/gr_est_congestion.rpt {*}[qc_env QB_GRT_ARGS {}]
    qc_log "global route done ([expr {[clock seconds] - $::T0}] s)"
    estimate_parasitics -global_routing
    qb_rep grt
    write_db $::OUT/db/grt_est.odb
    # QB_GRT_REPAIR 1 (results/pnr_slice2.md): setup repair at global-route parasitics, legalisation, incremental
    # global route of the changed nets, estimates again
    if {[qc_env QB_GRT_REPAIR 0]} {
        global_route -start_incremental
        repair_timing -setup -setup_margin 0.0 -repair_tns 100 -max_utilization [p MAX_UTIL]
        detailed_placement
        global_route -end_incremental -congestion_report_file $::OUT/rpt/gr_est2_congestion.rpt
        estimate_parasitics -global_routing
        qc_log "grt repair done ([expr {[clock seconds] - $::T0}] s)"
        unset -nocomplain ::qb_io_off
        qb_rep grtrep
    }
}
qc_log "grt_est done ([expr {[clock seconds] - $::T0}] s)"
