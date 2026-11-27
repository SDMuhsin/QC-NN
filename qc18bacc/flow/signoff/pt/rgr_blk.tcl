# PrimeTime sign-off of the routed regression block qb_lane_n at one corner (blocks/rgr/run.sh post / eco): the generic
# block sign-off signoff/pt/blk.tcl with the IO budget blocks/rgr/io_budget.tcl.  Classes beyond blk.tcl's: input ->
# reg, reg -> output, hold reg -> output.  No feedthrough.
# Chain IO as ICC2 (R109, blocks/rgr/icc2.cfg P(IO_LOAD) / P(IO_TRAN): the lanes abut like the columns, y_o[b] -> the next
# lane's x[b]): y_o[b] load = own x[b] net capacitance, x[b] input transition = own y_o[b] transition (fixed point,
# blocks/col/io_budget.tcl qb5_io_*), as the column's act / act_o (signoff/pt/col_blk.tcl).  [M] rg8d73b84a, ICC2 alone
# with it: PrimeTime with the SDC's 4 x INVD4 on y_o saw 24 max_transition violators in 4 corners, none in its references.
# Noise state (qbr_x_noise_state): x[*] driven by the SDC's input driving cell again (no driving cell in the timing state:
# set_input_transition replaces it), the other inputs keep theirs (blk.tcl qb_blk_sdc_noise_state's state).
set ::QB_BLK_IO_BUDGET [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/blocks/rgr/io_budget.tcl]
set ::QB_PT_NOISE_STATE qbr_x_noise_state
# qbr_x_noise_state [off]: timing state -> noise state (saves the four input transitions of every x port; error if a port
# has none, i.e. not in the timing state) / back (error if not in the noise state); returns a one-line record
proc qbr_x_noise_state {{mode on}} {
    set X [get_ports {x[*]}]
    set ks {input_transition_rise_max input_transition_fall_max input_transition_rise_min input_transition_fall_min}
    if {$mode eq "off"} {
        if {![info exists ::QBR_X_TIMING_STATE]} { error "qbr_x_noise_state off: not in the noise state" }
        remove_driving_cell $X
        foreach {p t} $::QBR_X_TIMING_STATE { foreach {e m} {rise max fall max rise min fall min} y $t { set_input_transition -$e -$m $y [get_ports $p] } }
        unset ::QBR_X_TIMING_STATE
        return "x timing state restored on [sizeof_collection $X] ports (input transitions, no driving cell)"
    }
    if {[info exists ::QBR_X_TIMING_STATE]} { error "qbr_x_noise_state: already in the noise state" }
    set st {}
    foreach_in_collection p $X {
        set t [lmap k $ks { get_attribute -quiet $p $k }]
        foreach x $t { if {![string is double -strict $x] || $x <= 0} { error "qbr_x_noise_state: [get_object_name $p] has no input transitions (not in the timing state)" } }
        lappend st [get_object_name $p] $t
    }
    set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -pin [lindex $::QC_DRV_IN 1] $X
    set ::QBR_X_TIMING_STATE $st
    return "[sizeof_collection $X] x ports driven by the SDC's input driving cell [join $::QC_DRV_IN /] (the other inputs: theirs)"
}
proc qb_blk_hook {stage args} {
    set in [remove_from_collection [all_inputs] [get_ports clk]]
    switch $stage {
        setup {
            qb5_io_load y_o [qb5_io_caps x {apply {p {get_attribute [get_nets -of_objects $p] total_capacitance_max}}}]
            update_timing
            set ::QB5_TRAN_RES [qb5_io_tran_fix x y_o]
        }
        head  { puts [lindex $args 0] [format "x_input_transition own y_o transition per bit, fixed-point residual %.5f ns; y_o load own x net" $::QB5_TRAN_RES] }
        max   { return [list in2reg [list -from $in -to [lindex $args 0]] reg2out [list -to [all_outputs]]] }
        hold  { return [list hold_reg2out [list -to [all_outputs]]] }
        tcq - lines - paths - noise - noise_count { return "" }
        default { error "qb_blk_hook: unknown stage $stage" }
    }
}
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/signoff/pt/blk.tcl]
