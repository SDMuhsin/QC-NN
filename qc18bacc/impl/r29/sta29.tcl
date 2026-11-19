# R29: OpenROAD view of given paths (R29_TO endpoints) at db R29_DB: placement-estimated parasitics (R29_PAR place),
# or the routed tt SPEF (R29_PAR spef: out/<top>_tt.spef).  report_checks with slew / cap / net fields.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R29_DB grt]
if {[qc_env R29_PAR place] eq "spef"} { read_spef $::OUT/out/qb_hub_tt.spef } else { estimate_parasitics -placement }
foreach e [qc_env R29_TO ""] {
    puts "R29STA endpoint $e"
    report_checks -path_delay max -to [get_pins $e] -fields {slew cap fanout input_pins nets} -digits 3
}
foreach n [qc_env R29_NETS ""] { report_net -digits 3 [get_nets $n] }
foreach c [qc_env R29_CMDS ""] { puts "R29STA cmd $c"; if {[catch {uplevel #0 $c} e]} { puts "R29STA err $e" } }
exit
