# PrimeTime sign-off of the routed regression block qb_lane_n at one corner (blocks/rgr/run.sh post / eco): the generic
# block sign-off signoff/pt/blk.tcl with the IO budget blocks/rgr/io_budget.tcl.  Classes beyond blk.tcl's: input ->
# reg, reg -> output, hold reg -> output.  No feedthrough, no block noise state: the SDC's driving cells hold every input
# port net (blk.tcl qb_blk_sdc_noise_state).
set ::QB_BLK_IO_BUDGET [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/blocks/rgr/io_budget.tcl]
proc qb_blk_hook {stage args} {
    set in [remove_from_collection [all_inputs] [get_ports clk]]
    switch $stage {
        setup { update_timing }
        max   { return [list in2reg [list -from $in -to [lindex $args 0]] reg2out [list -to [all_outputs]]] }
        hold  { return [list hold_reg2out [list -to [all_outputs]]] }
        tcq - head - lines - paths - noise { return "" }
        default { error "qb_blk_hook: unknown stage $stage" }
    }
}
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/signoff/pt/blk.tcl]
