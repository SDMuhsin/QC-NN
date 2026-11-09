# PrimeTime PX: SAIF power of one ablation array netlist (qc18acc/ablation/remote.sh power), with the settings of
# qc18acc/power/pt_power.tcl: tt (1.0 V, 25 C), ideal clock (pre-CTS), the synthesis SDC at QC_PERIOD, the SYNTHESIS
# wire-load model (WireAreaLowkCon enclosed), power_default_toggle_rate 0.
# Environment: QC_FLOW, SYN (DC run dir), TOP, QC_SDC, QC_PERIOD (ns), SAIF, OUT (report prefix).
# Outputs: ${OUT}.txt (power groups, switching-activity overview) and ${OUT}_cells.txt (every hierarchical cell:
#   internal / switching / leakage / total W) plus the top-level leaf cells (input registers) and the whole design.
source $::env(QC_FLOW)/common/lib.tcl
set top $::env(TOP)
set corner tt
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner]]
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
set_app_var power_default_toggle_rate 0
read_verilog $::env(SYN)/$top.v
current_design $top
link_design
set ::env(QC_CORNER) $corner
qc_apply_constraints $corner
set wlm [qc_wire_load $corner]
read_saif -strip_path tb_qab/dut $::env(SAIF)
update_power
set o $::env(OUT)
redirect ${o}_hier.rpt { report_power -nosplit -hierarchy -levels 4 }
set fh [open ${o}.txt w]
puts $fh "period_ns $::env(QC_PERIOD) corner $corner wire_load $wlm"
redirect -variable pr { report_power -nosplit }
puts $fh [regsub {^.*?(Power Group)} $pr {\1}]
redirect -variable sa { report_switching_activity }
puts $fh [regsub {^.*?(Switching Activity Overview)} $sa {\1}]
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
set fh [open ${o}_cells.txt w]
puts $fh "# hier_cell design internal switching leakage total (W)"
foreach_in_collection c [get_cells -hierarchical -filter "is_hierarchical==true"] {
    puts $fh "[get_object_name $c] [get_attribute $c ref_name] [pw $c]"
}
# leaf cells outside u_array (input registers, top glue) and the whole design
set all [get_cells -hierarchical -filter "is_hierarchical==false"]
set arr [get_cells -hierarchical -filter "is_hierarchical==false && full_name=~*u_array/*"]
puts $fh "NONARRAY_LEAF - [pw [remove_from_collection $all $arr]]"
puts $fh "DESIGN - [pw $all]"
close $fh
exit
