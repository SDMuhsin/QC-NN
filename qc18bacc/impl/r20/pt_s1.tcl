# R20 (results/r20.md): per-S1-register slack + full paths (pt_cls.tcl setup) of the routed act block at one corner (setup = impl/r7c/pt_blk.tcl:
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
# R20: per S1 register (band b, register k = bit / 32): worst slack and its startpoint; worst sel1->s1 and s1c->s1 paths in full
set fh [open $dir/r20_s1_$corner.txt w]
set P [get_timing_paths -delay_type max -max_paths 5000 -nworst 1 -to [get_pins -hier u_act/u_s1/u_b*/s1_reg*/D]]
array set W {}; array set SP {}
foreach_in_collection p $P {
    set ep [get_object_name [get_attribute $p endpoint]]
    if {![regexp {u_b([0-9]+)/s1_reg_([0-9]+)_} $ep -> b bit]} continue
    set k "$b [expr {$bit / 32}]"; set s [get_attribute $p slack]
    if {![info exists W($k)] || $s < $W($k)} { set W($k) $s; set SP($k) [get_object_name [get_attribute $p startpoint]] }
}
foreach k [lsort [array names W]] { puts $fh [format "s1 %s %.3f %s" $k $W($k) $SP($k)] }
close $fh
redirect $dir/r20_s1_paths_$corner.rpt {
  report_timing -nosplit -input_pins -nets -from [get_cells u_act/sel1a_reg_21_] -to [get_pins u_act/u_s1/u_b0/s1_reg_51_/D]
  report_timing -nosplit -input_pins -nets -to [get_pins -hier u_act/u_s1/u_b15/s1_reg*/D]
  report_timing -nosplit -input_pins -nets -to [get_pins -hier u_act/g_ctx_0__u_ctx/wer_reg*/D]
  report_timing -nosplit -input_pins -nets -from [get_ports s_q*]
  report_timing -nosplit -input_pins -nets -from [get_cells u_act/g_ctx_0__u_ctx/shq_reg*] -to [get_cells -hier lb_reg*]
}
exit
