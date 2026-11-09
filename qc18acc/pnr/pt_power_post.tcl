# PrimeTime PX: SAIF-based average power of the ROUTED QC18-ACC (qc18acc/pnr/power.sh), tt 1.0 V 25 C.
# As qc18acc/power/pt_power.tcl, but: the flat OpenROAD netlist (out/qa_top.v, with the clock tree, repair buffers,
# hold buffers, tie / antenna cells), the def2spef parasitics of the tt corner (out/qa_top_tt_pt.spef, no wire-load
# model), propagated clock, and the image-0 SDF SAIF flattened to the flat names (saif_flat.py).  Nets not in the
# SAIF (cells inserted by P&R) get their activity by propagation from the annotated nets (power_default_toggle_rate 0).
# Environment: QC_FLOW, PNR (P&R run dir), QC_SDC, QC_PERIOD, QC_EXTRA_DB_TT, SAIF, OUT (report prefix);
#   QA_MACROS (macro cell names, default the v2 set; power.sh sets the v3 set for QA_V=3, with the v3 blocks
#   u_wmem_e / u_wmem_o instead of u_wmem).
# Outputs: ${OUT}.txt (power groups, annotation), ${OUT}_blocks.txt (same keys as pt_power.tcl: first-level blocks
# by name prefix, macros by type, top-level glue; plus cts: the clock-tree cells inserted by CTS and
# clock_network group), ${OUT}_macros.txt (macro activity for macro_dat.py).
source $::env(QC_FLOW)/common/lib.tcl
set top qa_top
set corner tt
set pnr $::env(PNR)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs $corner]]
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
set_app_var power_default_toggle_rate 0
set_app_var read_parasitics_load_locations true
read_verilog $pnr/out/$top.v
current_design $top
link_design
set ::env(QC_CORNER) $corner
qc_apply_constraints $corner
set_propagated_clock [all_clocks]
set spef $pnr/out/${top}_${corner}_pt.spef
if {[file exists $spef]} { read_parasitics -format spef $spef } else { set spef "none: synthesis WLM [qc_wire_load $corner]" }
read_saif -strip_path qa_tb/dut $::env(SAIF)
update_timing
update_power
set o $::env(OUT)
redirect ${o}_annot.rpt { report_switching_activity -list_not_annotated -show_pin }
redirect ${o}_par.rpt { report_annotated_parasitics }
set fh [open ${o}.txt w]
puts $fh "period_ns $::env(QC_PERIOD) corner $corner netlist $pnr/out/$top.v spef $spef, propagated clock, saif $::env(SAIF)"
redirect -variable pr { report_power -nosplit }
puts $fh [regsub {^.*?(Power Group)} $pr {\1}]
redirect -variable sa { report_switching_activity }
puts $fh [regsub {^.*?(Switching Activity Overview)} $sa {\1}]
redirect -variable ap { report_annotated_parasitics }
puts $fh [regsub {^.*?(Annotated)} $ap {\1}]
set p [get_timing_paths -delay_type max -max_paths 1]
puts $fh [format "tt_setup_wns_ns %.3f (period %s, propagated clock, SPEF)" [get_attribute $p slack] $::env(QC_PERIOD)]
close $fh

proc pw {cells} {
    set s {0.0 0.0 0.0 0.0}
    foreach_in_collection c $cells {
        set v {}
        foreach a {internal_power switching_power leakage_power total_power} k {0 1 2 3} {
            if {[catch {set x [get_attribute $c $a]}] || $x eq ""} { set x 0.0 }
            lappend v [expr {[lindex $s $k] + $x}]
        }
        set s $v
    }
    return $s
}
set leaf [get_cells -hierarchical -filter "is_hierarchical==false"]
set fh [open ${o}_blocks.txt w]
puts $fh "# block internal_W switching_W leakage_W total_W   (period_ns $::env(QC_PERIOD), routed, SPEF tt)"
set done {}
set qa_macros [qc_env QA_MACROS "qa_act_1024x64m8 qa_wgt_4096x80m8 qa_par_4096x72m8 qa_dsc_256x32m2"]
set qa_blocks {u_pmem u_seq u_ppu u_host u_drain u_head u_xbar u_array u_wmem u_desc u_act u_agu}
if {[lsearch $qa_macros qa_act_512x64m4] >= 0} { set qa_blocks {u_pmem u_seq u_ppu u_host u_drain u_head u_xbar u_array u_wmem_e u_wmem_o u_desc u_act u_agu} }
foreach b $qa_blocks {
    set c [filter_collection $leaf "full_name=~$b/*"]
    puts $fh "hier:$b [pw $c]   n [sizeof_collection $c]"
    set done [add_to_collection $done $c]
}
foreach m $qa_macros {
    set mc [filter_collection $leaf "ref_name==$m"]
    puts $fh "macro:$m [pw $mc]   n [sizeof_collection $mc]"
}
set rest [remove_from_collection $leaf $done]
# clock tree inserted by OpenROAD CTS: clock buffers / inverters on clock nets outside the RTL hierarchy
set cts [filter_collection $rest "ref_name=~CKBD* || ref_name=~CKND* || full_name=~clkbuf* || full_name=~clkload*"]
puts $fh "cts:clock_tree_cells [pw $cts]   n [sizeof_collection $cts]"
puts $fh "glue:top_leaf_cells [pw [remove_from_collection $rest $cts]]   n [sizeof_collection [remove_from_collection $rest $cts]]"
set mcg [filter_collection $leaf "ref_name=~CKLNQD* && full_name=~*u_cg"]
if {[sizeof_collection $mcg]} { puts $fh "cg:macro_icg [pw $mcg]   n [sizeof_collection $mcg]" }
set icg [filter_collection $leaf "ref_name=~CKLNQD*"]
puts $fh "cg:all_icg [pw $icg]   n [sizeof_collection $icg]"
set allcts [filter_collection $leaf "full_name=~clkbuf* || full_name=~clkload*"]
puts $fh "cts:all_clkbuf_named [pw $allcts]   n [sizeof_collection $allcts]"
puts $fh "design:$top [pw $leaf]"
close $fh

proc pa {pin a} {
    if {[catch {set x [get_attribute [get_pins $pin] $a]}] || $x eq ""} {
        if {[catch {set x [get_attribute [get_nets -of_objects [get_pins $pin]] $a]}] || $x eq ""} { set x NA }
    }
    return $x
}
set fh [open ${o}_macros.txt w]
puts $fh "# instance ref clk_toggle_rate_per_ns cen_static_prob wen_static_prob   (period_ns $::env(QC_PERIOD))"
set mf {}; foreach m $qa_macros { lappend mf "ref_name==$m" }
foreach_in_collection c [filter_collection $leaf [join $mf { || }]] {
    set n [get_object_name $c]
    puts $fh "$n [get_attribute $c ref_name] [pa $n/CLK toggle_rate] [pa $n/CEN static_probability] [pa $n/WEN static_probability]"
}
close $fh
exit
