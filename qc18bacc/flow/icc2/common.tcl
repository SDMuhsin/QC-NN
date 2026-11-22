# Shared Tcl of every ICC2 step (flow/icc2/<step>.tcl; run by common/env.sh qb_icc2 from blocks/<b>/run.sh).
# Environment: QC_FLOW (flow/tsmc65, set by its common/tool.sh), QB_ICC2_CFG (block config, e.g. blocks/col/icc2.cfg),
#   QB_ICC2_RUN (run dir: <run>/<top>.nlib design library, rpt/, out/), QC_BUILD, QB_ICC2_CORES (default 16).
# Kit facts come from the flow/tsmc65 site files (site.tcl: libraries, tf, TLU+; site/pnr.tcl: LEF, GDS, cells, layers).
#   ::QB_NDM            standard-cell NDM (flow/icc2/libs.tcl), shared by every block under $QC_BUILD/icc2/ndm
#   qb_open <from> <to> open the design library, copy block label <from> to <to>, make it current, qb_timer
#   qb_timer            timer options of every design step: CCS receiver capacitance in delay / slew / max_cap
#                       (time.enable_ccs_rcv_cap, default false: ICC2 then loads nets with the NLDM pin cap while
#                       PrimeTime uses the CCS receiver model of the same _ccs.db, R55: 0.06 vs 0.09 pF on n1690)
#   qb_done <step> [as] save (as 1: save the current block as label <step>, the init step), log the step end in
#                       <run>/summary.txt, QB_ICC2_DONE marker for the wrapper
#   qb_qor <step>       QoR lines (cells, utilization, DRV count, WNS / TNS / NVE per scenario) + rpt/<step>_{qor,drv}.rpt
#   qb_line <text>      append a line to <run>/summary.txt (and the log)
set ::QBF [file normalize [file dirname [info script]]/..]
set ::QC_BUILD $::env(QC_BUILD)
source $::env(QC_FLOW)/common/lib.tcl
source $::env(QC_FLOW)/site/pnr.tcl
source $::env(QB_ICC2_CFG)
set ::R $::env(QB_ICC2_RUN)
set ::QB_NDM $::QC_BUILD/icc2/ndm/[file rootname [file tail $::QC_PNR_LEF]].ndm
set ::QB_LIB $::R/$P(TOP).nlib
file mkdir $::R/rpt $::R/out
if {[info commands set_host_options] ne ""} { set_host_options -max_cores [qc_env QB_ICC2_CORES 16] }

proc qb_line {t} {
    puts "QB_ICC2 $t"
    set f [open $::R/summary.txt a]; puts $f $t; close $f
}
proc qb_open {from to} {
    global P
    open_lib $::QB_LIB
    copy_block -from_block $P(TOP)/$from -to_block $P(TOP)/$to -force
    current_block $P(TOP)/$to
    link_block
    qb_timer
}
proc qb_timer {} {
    set_app_options -name time.enable_ccs_rcv_cap -value true
}
# one QoR line: setup WNS / TNS / violators per scenario, hold WNS per scenario, DRV counts, utilization
proc qb_qor {step} {
    redirect -variable q { report_qor -summary -nosplit }
    redirect $::R/rpt/${step}_qor.rpt { report_qor -summary -nosplit }
    redirect -variable c { report_constraints -all_violators -max_transition -max_capacitance -scenarios [all_scenarios] -nosplit }
    redirect $::R/rpt/${step}_drv.rpt { puts $c }
    if {[catch { redirect -variable ru { report_utilization }; regexp {Utilization Ratio:\s*([0-9.]+)} $ru -> u }] || ![info exists u]} { set u NA }
    qb_line "$step [clock format [clock seconds] -format %T -gmt 1] cells [sizeof_collection [get_flat_cells]] util $u drv_violations [expr {[regexp {Total number of violation\(s\):\s*(\d+)} $c -> n] ? $n : "NA"}]"
    foreach l [split $q "\n"] { if {[regexp {\((Setup|Hold)\)|^\s*Context} $l]} { qb_line "  $l" } }
}
proc qb_done {step {as 0}} {
    global P
    if {$as} { save_block -as $P(TOP)/$step } else { save_block }
    save_lib
    qb_line "$step done [clock format [clock seconds] -format %T -gmt 1]"
    puts "QB_ICC2_DONE $step"
}
