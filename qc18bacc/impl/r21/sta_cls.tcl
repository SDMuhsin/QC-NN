# R21 setup path classes of a hub checkpoint (QB_DB [place]) at its own parasitics estimate: worst slack and violating
# endpoint count per class in2out / in2reg / reg2out / reg2reg (+ per IO budget class of sdc.py) -> stdout R21_CLS lines.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env QB_DB place]
source $::env(QB_IO_BUDGET)
if {[qc_env QB21_PROP 0]} { set_propagated_clock [all_clocks] }
estimate_parasitics -placement
set ins [all_inputs]; set outs [all_outputs]; set regs [all_registers]
proc cls {k args} {
    set p [find_timing_paths -path_delay max -group_count 1000000 -endpoint_count 1 -slack_max 0 {*}$args]
    set n [llength $p]; set w NA
    if {$n} { set w [format %.3f [get_property [lindex $p 0] slack]] }
    puts "R21_CLS $k violating_endpoints $n worst $w"
}
cls in2out  -from $ins -to $outs
cls in2reg  -from $ins -to $regs
cls reg2out -from $regs -to $outs
cls reg2reg -from $regs -to $regs
foreach k [lsort [array names ::QB9_IO]] {
    set ps [get_ports -quiet $::QB9_IO($k)]
    if {![llength $ps]} continue
    if {[get_property [lindex $ps 0] direction] eq "input"} { cls "from_$k" -from $ps } else { cls "to_$k" -to $ps }
}
exit
