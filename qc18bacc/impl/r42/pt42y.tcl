# R42 diagnostic QB_PT_EXTRA (no pt39x): (1) how many not-annotated nets have a driver, sample of them;
# (2) the worst hold path per top class (seq stb, seq fq, wc_d -> SRAM D, hub->col pf) with clock expansion, nets, caps.
redirect -variable na { report_annotated_parasitics -list_not_annotated -max_nets 200000 }
set nd 0; set nn 0; set smp {}
foreach l [split $na "\n"] { if {[regexp {^\s*\d+\.\s+(\S+)\s+\(driver:\s*(.*)\)} $l -> n d]} { if {$d eq "<none>"} { incr nn } else { incr nd; if {[llength $smp] < 40} { lappend smp "$n $d" } } } }
puts $fh "R42NA not_annotated listed: driverless $nn with_driver $nd"
foreach s $smp { puts $fh "R42NA_DRV $s" }
set f [open $dir/rpt/r42_${corner}_holdpaths.rpt w]
foreach {k to} {stb */stb_reg*/D fq */fq_reg*/D wsram */g_mac_g_w_u_mac/D* pf */pf*} {
    redirect -variable r { report_timing -delay_type min -max_paths 1 -nosplit -path_type full_clock_expanded -input_pins -nets -capacitance -to [get_pins -hierarchical $to] }
    puts $f "##### $k\n$r"
}
close $f
