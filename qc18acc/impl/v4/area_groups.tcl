# Area groups of a QC18-ACC netlist (sourced by impl/v4/pt_hook.tcl at tt, or standalone in pt_shell after
# link_design; $out/rpt/area_groups.txt).  Leaf-cell areas (library cell area, um2), disjoint groups:
#   macro:<type>            the ARM macros
#   pe:<part>               inside the qa_pe instances: acc_regs (acc_q), shadow_regs (sh_out), adders (u_acc),
#                           rotators (u_rot*), clock (DC clock gates), muxes (PE top level: capture / shift-in)
#   array:rest              u_array outside the PEs
#   xbar:<part>             u_xbar: window (win), stage_a (sa), code (s3_code), ctrl (delay lines, lane mask)
#   act:<part>              u_act outside the macros: out_regs (macro output registers + read flags + macro ICGs,
#                           inside the u_ram wrappers), in_flops (cen / wen / addr at the macro pins), bank_select
#                           (ar_rdata), res_path (gr, pr_rdata), write_path (gw, wd_q), other
#   ppu, drain, head, agu, seq, host, wmem (weight wrappers), pmem, desc, glue (top-level leaf cells)
# Also the xbar fan-in: start points in the fan-in cone of one window-register D pin and of one stage-A D pin.
proc qa_leaf {pat} { return [get_cells -quiet -hierarchical -filter "is_hierarchical==false && full_name=~$pat"] }
proc qa_area {c} {
    set a 0.0
    foreach_in_collection x $c { set v [get_attribute -quiet [get_lib_cells -quiet -of_objects $x] area]; if {$v ne ""} { set a [expr {$a + $v}] } }
    return $a
}
set qa_all [get_cells -quiet -hierarchical -filter "is_hierarchical==false"]
set qa_used [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~qa_*"]
set qa_rows {}
foreach m {qa_act qa_wgt qa_par qa_dsc} {
    set c [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~${m}_*"]
    lappend qa_rows [list macro:$m [qa_area $c] [sizeof_collection $c]]
}
proc qa_take {name pat} {
    upvar qa_used used qa_rows rows
    set c [remove_from_collection [qa_leaf $pat] $used]
    set used [add_to_collection $used $c]
    lappend rows [list $name [qa_area $c] [sizeof_collection $c]]
}
qa_take pe:acc_regs     "u_array/*u_pe/acc_q_reg*"
qa_take pe:shadow_regs  "u_array/*u_pe/sh_out_reg*"
qa_take pe:adders       "u_array/*u_pe/u_acc/*"
qa_take pe:rotators     "u_array/*u_pe/u_rot*"
qa_take pe:clock        "u_array/*u_pe/clk_gate*"
qa_take pe:muxes        "u_array/*u_pe/*"
qa_take array:rest      "u_array/*"
qa_take xbar:window     "u_xbar/win_reg*"
qa_take xbar:stage_a    "u_xbar/sa_reg*"
qa_take xbar:code       "u_xbar/s3_code_reg*"
qa_take xbar:ctrl       "u_xbar/*"
qa_take act:out_regs    "u_act/*u_ram/*"
qa_take act:write_wd    "u_act/*wd_q_reg*"
qa_take act:in_flops    "u_act/*_q_reg*"
qa_take act:bank_select "u_act/ar_rdata_reg*"
qa_take act:res_path    "u_act/g*r_reg*"
qa_take act:res_path2   "u_act/pr_rdata_reg*"
qa_take act:write_path  "u_act/gw_*"
qa_take act:other       "u_act/*"
qa_take ppu             "g_ppu*"
qa_take ppu_v3          "u_ppu/*"
qa_take drain           "u_drain/*"
qa_take head            "u_head/*"
qa_take agu             "u_agu/*"
qa_take seq             "u_seq/*"
qa_take host            "u_host/*"
qa_take wmem            "u_wmem*"
qa_take pmem            "u_pmem/*"
qa_take desc            "u_desc/*"
lappend qa_rows [list glue [qa_area [remove_from_collection $qa_all $qa_used]] [sizeof_collection [remove_from_collection $qa_all $qa_used]]]
set fa [open $out/rpt/area_groups.txt w]
puts $fa "# group area_um2 leaf_cells   (library cell areas; total [format %.0f [qa_area $qa_all]] um2, [sizeof_collection $qa_all] leaf cells)"
foreach r $qa_rows { puts $fa [format "%s %.0f %d" {*}$r] }
# xbar fan-in: start points of the cone of one window-register / stage-A D pin (v3 has no stage A)
foreach {k pat} {window "u_xbar/win_reg*" stage_a "u_xbar/sa_reg*" bank_select "u_act/ar_rdata_reg*" res_group "u_act/gr_reg*"
                 res_port "u_act/pr_rdata_reg*" write_data "u_act/*wd_q_reg*" v3_res_word "u_act/pr_rdata*"} {
    set c [index_collection [qa_leaf $pat] 0]
    if {![sizeof_collection $c]} { continue }
    set d [get_pins -quiet -of_objects $c -filter "direction==in && (lib_pin_name==D || lib_pin_name==DA || lib_pin_name==DB)"]
    set sp [all_fanin -to $d -startpoints_only -flat]
    set nm 0; set nr 0
    foreach_in_collection s $sp {
        set cc [get_cells -quiet -of_objects $s]
        if {[sizeof_collection $cc] && [regexp {^qa_} [get_attribute $cc ref_name]]} { incr nm } else { incr nr }
    }
    puts $fa [format "fanin:%s pin %s startpoints %d macro_pins %d other %d" $k [get_object_name $d] [sizeof_collection $sp] $nm $nr]
}
close $fa
puts $fh "area_groups $out/rpt/area_groups.txt"
