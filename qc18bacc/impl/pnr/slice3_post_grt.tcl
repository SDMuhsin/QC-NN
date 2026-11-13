# POST_GRT_TCL of slice3.cfg (results/pnr_slice3.md): estimates at global-route parasitics inside the route step (no
# separate grt_est.tcl run): all-path summary, then IO delays removed and reg2reg worst slack, worst slack per class
# (PE row, fused / wide lane, decode / BR), hold; nothing is changed in the design.
qc_to $::OUT/rpt/grt_all.rpt { report_checks -path_delay max -format full_clock_expanded -fields {input_pins} -digits 3 }
unset_input_delay -clock [get_clocks qb_clk] [all_inputs]
unset_output_delay -clock [get_clocks qb_clk] [all_outputs]
qc_to $::OUT/rpt/grt_r2r.rpt { report_checks -path_delay max -format full_clock_expanded -fields {input_pins slew cap fanout} -digits 3 }
qc_to $::OUT/rpt/grt_hold.rpt { report_checks -path_delay min -format full_clock_expanded -digits 3 }
qc_summary "grt_r2r [join [qc_timing_lines grt_r2r] { | }]"
set f $::OUT/rpt/slice3_grt.ends.rpt
qc_to $f { report_checks -path_delay max -group_count 5000 -endpoint_count 1 -format end }
set fh [open $f]; set ends [read $fh]; close $fh
array set w {}
foreach line [split $ends \n] {
    if {[llength $line] < 4 || ![regexp {(-?[0-9]+\.[0-9]+)\s*(\(VIOLATED\))?\s*$} $line -> sl]} { continue }
    set pn [lindex $line 0]
    if {[regexp {g_r_(\d+)__g_c_0__u_pe/} $pn -> r]} { set c pe[format %02d $r] } elseif {[regexp {u_lf/} $pn]} { set c lane_f } \
        elseif {[regexp {u_lw/} $pn]} { set c lane_w } elseif {[regexp {u_(br|dec)|cdr_reg|ctlr_reg} $pn]} { set c dec_br } \
        elseif {[regexp {/} $pn]} { set c other } else { set c port }
    if {![info exists w($c)] || $sl < $w($c)} { set w($c) $sl }
}
qc_summary "slice3_grt_class_wns [lmap k [lsort [array names w]] {format %s=%.3f $k $w($k)}]"
qc_to $::OUT/rpt/grt_skew.rpt { report_clock_skew }
