# PrimeTime PX: SAIF-based average power of the QC18-ACC netlist (top qa_top) at tt (driven by qc18acc/power/power.sh).
# Same settings as nn/gls/pt_power.tcl: tt library (1.0 V, 25 C) + macro tt .db, ideal clock (pre-CTS: no clock
# tree, ICGs only), the synthesis SDC (impl/constraints.sdc) at QC_PERIOD, and the SYNTHESIS wire-load model
# (qc_wire_load: WireAreaLowkCon enclosed; mandatory, see the WLM erratum of nn/results/gls_power.md).
# Environment: QC_FLOW (flow/tsmc65), SYN (DC run dir: qa_top.v), QC_SDC, QC_PERIOD (ns), QC_EXTRA_DB_TT (macro .db),
#   SAIF (file; toggles per cycle must match QC_PERIOD: power.sh rescales the SAIF times), OUT (report prefix).
# Outputs: ${OUT}.txt (power groups, hierarchy depth 1, annotation; design names only) and ${OUT}_blocks.txt
#   (internal / switching / leakage / total W per first-level block, wrapper logic without its macros, the macros by
#   type, top-level glue cells).
# Optional (lowv.sh): QC_PT_CORNER (corner key, default tt) and QC_PT_LIB (cell library of that key, e.g.
#   tcbn65gplustc0d8_ccs for tt 0.8 V; the macro .db of QC_EXTRA_DB_TT are linked unchanged).
source $::env(QC_FLOW)/common/lib.tcl
set top qa_top
set corner [qc_env QC_PT_CORNER tt]
if {[qc_env QC_PT_LIB] ne ""} { set ::QC_LIB($corner) $::env(QC_PT_LIB) }
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs tt]]
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
# a net missing from the SAIF with no annotated fan-in is static (toggle 0), not the 0.1 / cycle default
set_app_var power_default_toggle_rate 0
read_verilog $::env(SYN)/$top.v
current_design $top
link_design
set ::env(QC_CORNER) $corner
qc_apply_constraints $corner
set wlm [qc_wire_load $corner]
read_saif -strip_path qa_tb/dut $::env(SAIF)
update_power
set o $::env(OUT)
redirect ${o}_annot.rpt { report_switching_activity -list_not_annotated -show_pin }
redirect ${o}_hier.rpt  { report_power -nosplit -hierarchy -levels 3 }
set fh [open ${o}.txt w]
puts $fh "period_ns $::env(QC_PERIOD) corner $corner lib $::QC_LIB($corner) wire_load $wlm saif $::env(SAIF)"
redirect -variable pr { report_power -nosplit }
puts $fh [regsub {^.*?(Power Group)} $pr {\1}]
redirect -variable ph { report_power -nosplit -hierarchy -levels 1 }
puts $fh [regsub {^.*?(Hierarchy)} $ph {\1}]
redirect -variable sa { report_switching_activity }
puts $fh [regsub {^.*?(Switching Activity Overview)} $sa {\1}]
close $fh

# ---- block table
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
set fh [open ${o}_blocks.txt w]
puts $fh "# block internal_W switching_W leakage_W total_W   (period_ns $::env(QC_PERIOD), wire_load $wlm)"
foreach_in_collection c [get_cells -filter "is_hierarchical==true"] {
    puts $fh "hier:[get_object_name $c] [pw $c]"
}
foreach m {qa_act_1024x64m8 qa_wgt_4096x80m8 qa_par_4096x72m8 qa_dsc_256x32m2} {
    set mc [get_cells -quiet -hierarchical -filter "ref_name==$m"]
    puts $fh "macro:$m [pw $mc]   n [sizeof_collection $mc]"
}
puts $fh "glue:top_leaf_cells [pw [get_cells -quiet -filter is_hierarchical==false]]"
# v2: the macro clock gates (hw/tech/qa_sram_tech.sv u_cg, inside the memory wrappers' logic)
set mcg [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~CKLNQD* && full_name=~*u_cg"]
if {[sizeof_collection $mcg]} { puts $fh "cg:macro_icg [pw $mcg]   n [sizeof_collection $mcg]" }
puts $fh "design:$top [pw [get_cells -quiet -hierarchical -filter is_hierarchical==false]]"
close $fh

# ---- macro activity for the datatable access-energy model (power.sh -> macro_dat.py): the macro .lib carries no
# CLK access energy (every CLK internal_power table is 0; only pin energies, e.g. WEN), so PT's macro dynamic power
# misses the read / deselect energy.  Per instance: CLK toggles per ns, P(CEN=1), P(WEN=1) of the SAIF.
proc pa {pin a} {
    if {[catch {set x [get_attribute [get_pins $pin] $a]}] || $x eq ""} {
        if {[catch {set x [get_attribute [get_nets -of_objects [get_pins $pin]] $a]}] || $x eq ""} { set x NA }
    }
    return $x
}
set fh [open ${o}_macros.txt w]
puts $fh "# instance ref clk_toggle_rate_per_ns cen_static_prob wen_static_prob   (period_ns $::env(QC_PERIOD))"
foreach_in_collection c [get_cells -hierarchical -filter "is_hierarchical==false && (ref_name==qa_act_1024x64m8 || ref_name==qa_wgt_4096x80m8 || ref_name==qa_par_4096x72m8 || ref_name==qa_dsc_256x32m2)"] {
    set n [get_object_name $c]
    puts $fh "$n [get_attribute $c ref_name] [pa $n/CLK toggle_rate] [pa $n/CEN static_probability] [pa $n/WEN static_probability]"
}
close $fh
exit
