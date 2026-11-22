# PrimeTime report of the qc18bacc microblocks (QC_PT_HOOK of flow/tsmc65/sta/run_pt.sh; $fh, $out, $corner).
# fmax = 1 / (period - WNS) of the worst setup path (setup uncertainty included), as qc18acc/impl/pt_hook.tcl.
set per [get_attribute [get_clocks qb_clk] period]
set p [get_timing_paths -delay_type max -max_paths 1 -group qb_clk]
if {[sizeof_collection $p]} {
    set s [get_attribute $p slack]
    puts $fh [format "clock qb_clk period_ns %.3f wns_ns %.3f fmax_mhz %.1f path %s -> %s" $per $s \
        [expr {1000.0 / ($per - $s)}] [get_object_name [get_attribute $p startpoint]] \
        [get_object_name [get_attribute $p endpoint]]]
}
redirect $out/rpt/pt_${corner}_qb_clk_max.rpt { report_timing -group qb_clk -max_paths 10 -nworst 1 -nosplit -input_pins }
