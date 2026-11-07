# PrimeTime PX: SAIF power of one ablation core netlist at tt (qcacc/ablation/remote.sh power), as nn/gls/pt_power.tcl.
# Environment: QC_FLOW, SYN (DC run dir), TOP, QC_SDC, QC_PERIOD (ns), SAIF, OUT (report prefix).
# Pre-CTS: ideal clock network.  Net capacitance: the synthesis wire-load model (site.tcl QC_WLM_GROUP, as DC / PT
#   timing) unless ABL_PT_ZWLM=1: then the library default (WireAreaForZero -> zero wire cap), which is what
#   nn/gls/pt_power.tcl (used for the M3 / baseline cluster power) gets, since it never selects a wire-load model.
source $::env(QC_FLOW)/common/lib.tcl
set top $::env(TOP)
set corner tt
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner]]
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
set_app_var power_default_toggle_rate 0   ;# Questa's SAIF omits never-toggling nets (as nn/gls/pt_power.tcl)
read_verilog $::env(SYN)/$top.v
current_design $top
link_design
set ::env(QC_CORNER) $corner
qc_apply_constraints $corner
set wlm lib_default
if {![info exists ::env(ABL_PT_ZWLM)] || $::env(ABL_PT_ZWLM) ne "1"} { set wlm [qc_wire_load $corner] }
read_saif -strip_path /tb_abl/dut $::env(SAIF)
update_power
set o $::env(OUT)
redirect ${o}_power.rpt { report_power -nosplit -verbose }
redirect ${o}_hier.rpt  { report_power -nosplit -hierarchy -levels 4 }
# summary: design hierarchy and power groups only (no library cell names)
set fh [open ${o}.txt w]
puts $fh "period_ns $::env(QC_PERIOD) corner $corner wire_load $wlm"
redirect -variable pr { report_power -nosplit }
puts $fh [regsub {^.*?(Power Group)} $pr {\1}]
redirect -variable sa { report_switching_activity }
puts $fh [regsub {^.*?(Switching Activity Overview)} $sa {\1}]
close $fh
# every hierarchical cell: internal switching leakage total (W)
set fh [open ${o}_cells.txt w]
puts $fh "# hier_cell ref internal switching leakage total (W)"
foreach_in_collection c [get_cells -hierarchical -filter "is_hierarchical==true"] {
  set v {}
  foreach a {internal_power switching_power leakage_power total_power} {
    if {[catch {set x [get_attribute $c $a]}] || $x eq ""} { set x NA }
    lappend v $x
  }
  puts $fh "[get_object_name $c] [get_attribute $c ref_name] [join $v { }]"
}
close $fh
exit
