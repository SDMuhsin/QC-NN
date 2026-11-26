# PrimeTime sign-off of the routed column block qb_col_blk at one corner (results/r5a.md): the generic block sign-off
# signoff/pt/blk.tcl with the column's hooks.  IO budget blocks/col/io_budget.tcl.  Column classes: act -> reg, act ->
# act_o (feedthrough), north in -> reg, south in -> reg, reg -> south out, hold act -> act_o, the feedthrough delay; act
# feedthrough setup (dont_touch QB5_FT cells, act_o load, act input transition fixed point); noise on the act noise state
# (qb5_act_noise_driver) with the act load pins as their own line and gate (act_noise).
set ::QB_BLK_IO_BUDGET [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/blocks/col/io_budget.tcl]
# the block's noise-only analysis state (R92, PI decision): "<command>" enters it, "<command> off" returns to the timing
# state set up by the setup hook; the sign-off enters it last (blk.tcl), the ECO around its noise passes (signoff/pt/drv_eco.tcl)
set ::QB_PT_NOISE_STATE qb5_act_noise_driver
proc qb_blk_hook {stage args} {
    switch $stage {
        setup {
            # (with the act driving cell QB5_FT of qb5_io_apply, replaced by the measured act transition below, R71)
            # feedthroughs: each act_o driven by one QB5_FT cell (error otherwise), cells and act_o nets dont_touch as in
            # ICC2 init (the DMSA ECO neither resizes nor re-buffers them)
            set_dont_touch [qb5_ft_cells] true
            set_dont_touch [get_nets -of_objects [get_ports {act_o[*]}]] true
            # act_o load = this block's own act[b] net (next column's act pin), per bit, on the routed SPEF
            qb5_act_o_load [qb5_act_o_caps {apply {p {get_attribute [get_nets -of_objects $p] total_capacitance_max}}}]
            update_timing
            # act[b] input transition = own act_o[b] transition, iterated to a fixed point (io_budget.tcl qb5_act_tran_fix, R71)
            set ::QB5_TRAN_RES [qb5_act_tran_fix]
        }
        tcq { return [format " act_min_input_delay_ns %.4f (+ QC_ACT_HOLD_HUB)" [qb5_act_in_min $::Le $::Tq]] }
        head { puts [lindex $args 0] [format "act_input_transition own act_o transition per bit, fixed-point residual %.5f ns" $::QB5_TRAN_RES] }
        max {
            set regs [lindex $args 0]
            return [list \
                act2reg   [list -from [get_ports {act[*]}] -to $regs] \
                act2act_o [list -from [get_ports {act[*]}] -to [get_ports {act_o[*]}]] \
                north2reg [list -from [get_ports {cd[*] ctl[*] t2[*]}]] \
                south2reg [list -from [get_ports {pf[*] pw[*] p_ld w_ld s_rd[*] w_r[*] f_vld f_src f_sh w_vld w_sh}]] \
                reg2south [list -to [get_ports {f_y[*] f_b[*] w_y[*] w_b[*] f_vld_o w_vld_o b2[*] b2_vld}]]]
        }
        hold { return [list hold_act2act_o [list -from [get_ports {act[*]}] -to [get_ports {act_o[*]}]]] }
        lines {
            # feedthrough delay act -> act_o (no IO delays): max / min over the 4608 bits
            set fh [lindex $args 0]
            set ft [get_timing_paths -delay_type max -max_paths 1 -from [get_ports {act[*]}] -to [get_ports {act_o[*]}]]
            set ftn [get_timing_paths -delay_type min -max_paths 1 -from [get_ports {act[*]}] -to [get_ports {act_o[*]}]]
            set ain [expr {0.55 * $::per + $::L}]; set ainm [qb5_act_in_min $::Le $::Tq]
            if {[sizeof_collection $ft]} { puts $fh [format "feedthrough_delay_ns max %.3f min %.3f (budget %.3f = 0.07 P)" \
                [expr {[get_attribute $ft arrival] - $ain}] [expr {[get_attribute $ftn arrival] - $ainm}] [expr {0.07 * $::per}]] }
        }
        paths {
            lassign $args r pd
            qb_pt_paths ${r}_ft.rpt [list -max_paths 3 -from [get_ports {act[*]}] -to [get_ports {act_o[*]}] {*}$pd] \
                [list -delay_type min -max_paths 3 -from [get_ports {act[*]}] -to [get_ports {act_o[*]}] {*}$pd]
        }
        noise {
            # the act load pins on the QB5_FT driver of the noise state: their own line and gate
            set fh [lindex $args 0]
            lassign [qb_pt_noise_pins [get_pins -leaf -of_objects [get_nets -of_objects [get_ports {act[*]}]] -filter "direction==in"]] an at
            puts $fh "act_noise $at"
            puts "QB_PT_SIGNOFF act_noise $an"
        }
        default { error "qb_blk_hook: unknown stage $stage" }
    }
}
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/signoff/pt/blk.tcl]
