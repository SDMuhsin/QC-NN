# R8d PT hook (impl/r8a/pt_xtra.tcl + classes b2r = column b2 -> b2r, top_glue_x = top_glue not started in the
# column blocks):
# R8a PT hook: impl/r4/pt_class.tcl (classes as R7h) + extra classes with working regexes (pt_class top_glue /
# to_macro / from_macro never match the DC names) + the 12 worst endpoints per class + full worst path per class.
source [file dirname [info script]]/../r4/pt_class.tcl
set xcl {
    head           {u_head/}                     {.*}
    act_supply     {u_top/u_act/}                {.*}
    seq            {u_seq/}                      {.*}
    prm            {u_prm/}                      {.*}
    top_glue       {^u_top/[^/]+/[^/]+$}         {.*}
    top_glue_x     {^u_top/[^/]+/[^/]+$}         {^(?!u_top/u_core/)}
    b2r            {^u_top/b2r_reg}              {.*}
    to_macro       {u_mac/[^/]+$}                {.*}
    from_macro     {.*}                          {u_mac/}
    chip_glue      {^[^/]+/[^/]+$}               {.*}
    core_in        {u_top/u_core/}               {.*}
}
set xp [get_timing_paths -delay_type max -max_paths 300000 -nworst 1 -slack_lesser_than 0.20 -group qb_clk]
array unset xn; array unset xb
foreach_in_collection p $xp {
    set e [get_object_name [get_attribute $p endpoint]]
    set s [get_object_name [get_attribute $p startpoint]]
    foreach {cl re rs} $xcl {
        if {[regexp $re $e] && [regexp $rs $s]} {
            if {![info exists xn($cl)]} { set xn($cl) 0 }
            if {$xn($cl) < 12} { lappend xb($cl) [list [get_attribute $p slack] $s $e] }
            incr xn($cl)
        }
    }
}
set xf [open $out/rpt/pt_${corner}_r8d.rpt w]
foreach {cl re rs} $xcl {
    if {![info exists xn($cl)]} { puts $fh "xclass $cl none_below_0.20"; continue }
    set sl [lindex [lindex $xb($cl) 0] 0]
    puts $fh [format "xclass %-11s slack_ns %.3f fmax_mhz %.1f n_below_0.20 %d %s -> %s" $cl $sl \
        [expr {1000.0 / ($per - $sl)}] $xn($cl) [lindex [lindex $xb($cl) 0] 1] [lindex [lindex $xb($cl) 0] 2]]
    puts $xf "#### class $cl ($xn($cl) endpoints with slack < 0.20)"
    foreach t $xb($cl) { puts $xf [format "  %.3f %s -> %s" {*}$t] }
    set e0 [lindex [lindex $xb($cl) 0] 2]
    set ep [get_pins -quiet $e0]; if {![sizeof_collection $ep]} { set ep [get_ports $e0] }
    redirect -variable rt { report_timing -to $ep -nosplit -input_pins -significant_digits 3 }
    puts $xf $rt
    if {$cl eq "core_in"} {                                     ;# ETM artefact check: slew at the block act pin
        foreach_in_collection q [get_pins $e0] {
            puts $xf [format "core_in endpoint %s actual_transition_max rise %s fall %s" $e0 \
                [get_attribute $q actual_rise_transition_max] [get_attribute $q actual_fall_transition_max]]
        }
    }
}
close $xf
# R8d: fan-out of the top b2 capture (the top-side path that QB_COL_B2R would start at the column b2 pins)
foreach {nm pat} {b2r_from {u_top/b2r_reg*} b2fd_from {u_top/b2f_d_reg*}} {
    set cs [get_cells -quiet $pat]
    if {![sizeof_collection $cs]} { puts $fh "xfrom $nm none"; continue }
    set p [get_timing_paths -from $cs -max_paths 1 -group qb_clk]
    puts $fh [format "xfrom %-9s slack_ns %.3f arrival_ns %.3f %s -> %s" $nm [get_attribute $p slack] \
        [get_attribute $p arrival] [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
}
