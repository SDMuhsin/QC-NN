# R20 (results/r20.md): path-class breakdown of the routed act block at one corner (setup = impl/r7c/pt_blk.tcl:
# netlist + def2spef SPEF, propagated clock, IO budget shifted by L).  Writes $QC_PNR_OUT/r20_cls_<corner>.txt:
#   * violating endpoints (slack < 0 at QC_PERIOD) per (start class -> end class): count, worst slack
#   * worst path of each class: launch / capture latency, cell vs net delay, cells, buffers, max fanout
#   * clock latency (CP arrival) min / p50 / max per register group
set t0 [clock seconds]
source $::env(QC_FLOW)/common/lib.tcl
set top $::env(QC_TOP); set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner]]
read_verilog $dir/out/$top.v
current_design $top
link_design
qc_apply_constraints $corner
set_propagated_clock [all_clocks]
read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef
update_timing
set per [get_attribute [get_clocks qb_clk] period]
redirect -variable cs { report_clock_timing -type summary -clock qb_clk -nosplit }
set lat {}
foreach k {{Maximum setup launch latency} {Minimum setup capture latency}} {
    if {[regexp "$k:\\s*\\n\\s*\\S+\\s+(\[-0-9.\]+)" $cs -> v]} { lappend lat $v }
}
set L [expr {[llength $lat] ? ([tcl::mathfunc::max {*}$lat] + [tcl::mathfunc::min {*}$lat]) / 2.0 : 0.6}]
source $::env(QB20_ROOT)/impl/r7c/budget.tcl
qb7_io_apply $per $L
update_timing
proc cls {n} {
    foreach {re c} {
        {^(tgo|start|c_|l_ok|l_seq|f_)} cin {^(s_q|m_q)} din {s1c_r_reg} s1c {u_s1/u_b[0-9]+/s1_reg} s1 {s1_reg} s1
        {u_lb/lb_reg} lb {wer_reg} wer {sel2_reg} sel2 {sel1[ab]?_reg} sel1 {shq} shq {ival_reg} ival {dsc_reg} dsc
        {u_s2/act_reg} act {u_dist} dist {sdq_reg} sdq {rdq_reg} rdq {u_ctx} ctx {^act\[} actout {^u_act/[^/]+_reg} actreg } {
        if {[regexp $re $n]} { return $c }
    }
    return other
}
set fh [open $dir/r20_cls_$corner.txt w]
puts $fh "# R20 pt_cls corner $corner period $per L [format %.3f $L] (latencies $lat)"
set P [get_timing_paths -delay_type max -max_paths 100000 -nworst 1 -slack_lesser_than 0.0]
array set N {}; array set W {}; array set EX {}
foreach_in_collection p $P {
    set sp [get_object_name [get_attribute $p startpoint]]; set ep [get_object_name [get_attribute $p endpoint]]
    set k "[cls $sp]->[cls $ep]"; set s [get_attribute $p slack]
    incr N($k)
    if {![info exists W($k)] || $s < $W($k)} { set W($k) $s; set EX($k) "$sp -> $ep" }
}
puts $fh "violating endpoints [sizeof_collection $P]"
foreach k [lsort -command {apply {{a b} {expr {$::W($a) < $::W($b) ? -1 : 1}}}} [array names N]] {
    puts $fh [format "  %-16s n %6d worst %7.3f fmax %6.1f  %s" $k $N($k) $W($k) [expr {1000.0 / ($per - $W($k))}] $EX($k)]
}
# worst path per class: breakdown
foreach k [lsort [array names EX]] {
    lassign [split $EX($k) " "] sp - ep
    set p [get_timing_paths -delay_type max -from $sp -to $ep]
    set cl 0.0; set nt 0.0; set nc 0; set nb 0; set fo 0; set prev ""
    set pts [get_attribute $p points]
    set la [get_attribute $p startpoint_clock_latency]; set ca [get_attribute $p endpoint_clock_latency]
    foreach_in_collection pt $pts {
        set o [get_attribute $pt object]; set ar [get_attribute $pt arrival]
        if {[get_attribute -quiet $o object_class] eq "pin"} {
            set dirn [get_attribute $o direction]
            if {$prev ne ""} {
                set d [expr {$ar - $prev}]
                if {$dirn eq "out"} { set cl [expr {$cl + $d}]; incr nc
                    set rc [get_attribute [get_cells -of $o] ref_name]
                    if {[regexp {^(BUFF|CKB|DEL)} $rc]} { incr nb }
                    set f [sizeof_collection [get_pins -quiet -leaf -of [get_nets -of $o] -filter "direction==in"]]
                    if {$f > $fo} { set fo $f }
                } else { set nt [expr {$nt + $d}] }
            }
        } elseif {$prev ne ""} { set nt [expr {$nt + $ar - $prev}] }
        set prev $ar
    }
    puts $fh [format "path %-16s slack %7.3f launch_lat %.3f capture_lat %.3f cell %.3f (%d cells, %d buf) net %.3f maxfo %d  %s" \
        $k [get_attribute $p slack] $la $ca $cl $nc $nb $nt $fo $EX($k)]
}
# clock latency per register group (CP pin max rise arrival)
foreach {g pat} {s1c {u_act/s1c_r_reg*} s1 {u_act/u_s1/u_b*/s1_reg*} lb {u_act/g_ctx_*__u_ctx/u_lb/lb_reg*} wer {u_act/g_ctx_*__u_ctx/wer_reg*}
                 sel2 {u_act/sel2_reg*} act {u_act/u_s2/act_reg*} dist {u_dist/q_reg*}} {
    set cells [get_cells -quiet -hier $pat -filter "is_sequential==true"]
    if {![sizeof_collection $cells]} { puts $fh "lat $g none"; continue }
    set v {}
    foreach_in_collection c [get_pins -quiet -of $cells -filter "lib_pin_name==CP"] { set a [get_attribute -quiet $c max_rise_arrival]; if {$a ne ""} { lappend v $a } }
    set v [lsort -real $v]; set n [llength $v]
    if {$n} { puts $fh [format "lat %-5s n %6d min %.3f p50 %.3f p90 %.3f max %.3f" $g $n [lindex $v 0] [lindex $v [expr {$n/2}]] [lindex $v [expr {$n*9/10}]] [lindex $v end]] }
}
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
