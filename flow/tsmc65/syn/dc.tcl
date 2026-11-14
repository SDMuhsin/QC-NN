# DC synthesis of one design (driven by syn/run_dc.sh; see there for the environment).
set t0 [clock seconds]
source $::env(QC_FLOW)/common/lib.tcl
set top    $::env(QC_TOP)
set corner $::env(QC_CORNER)
set out    $::env(QC_OUT)
set_host_options -max_cores [qc_env QC_CORES 8]
file mkdir [qc_env QC_ALIB $out/../alib]
set_app_var alib_library_analysis_path [qc_env QC_ALIB $out/../alib]   ;# library analysis cache, shared by runs

# ---- libraries
set_app_var search_path [concat . $::QC_LIBDIR [get_app_var search_path]]
set_app_var target_library [list [qc_db $corner]]
set_app_var synthetic_library dw_foundation.sldb
set_app_var link_library [concat * [qc_db $corner] [qc_extra_dbs $corner] dw_foundation.sldb]
if {$corner ne "ff"} {
    set_min_library [qc_db $corner] -min_version [qc_db ff]
    foreach m [qc_extra_dbs $corner] f [qc_extra_dbs ff] { if {$m ne "" && $f ne ""} { set_min_library $m -min_version $f } }
}
if {[llength [qc_extra_dbs $corner]]} { puts "QC_LIBS [llength [qc_extra_dbs $corner]] extra link libraries ($corner)" }
if {[llength $::QC_DONT_USE]} {
    set_dont_use [get_lib_cells [lmap c $::QC_DONT_USE {string cat $::QC_LIB($corner)/$c}]]
}
if {$::env(QC_TOPO)} {
    create_mw_lib -technology $::QC_TF -mw_reference_library $::QC_MW_REF $out/mw
    open_mw_lib $out/mw
    set_tlu_plus_files -max_tluplus $::QC_TLU/$::QC_TLU_FILE($corner) \
        -min_tluplus $::QC_TLU/$::QC_TLU_FILE(ff) -tech2itf_map $::QC_TLU_MAP
}

# ---- read RTL (flat file list; SystemVerilog, VHDL by extension)
set fl [qc_flist $::env(QC_FLIST)]
set_app_var search_path [concat [dict get $fl incdirs] [get_app_var search_path]]
catch {set_app_var hdlin_sverilog_std 2017}
define_design_lib WORK -path $out/work
set defs [concat SYNTHESIS [dict get $fl defines]]
set sv  [lsearch -all -inline -not -regexp [dict get $fl files] {\.vhdl?$}]
set vhd [lsearch -all -inline -regexp      [dict get $fl files] {\.vhdl?$}]
puts "QC_RTL [llength $sv] SV/Verilog files, [llength $vhd] VHDL files, [llength [dict get $fl incdirs]] incdirs, defines: $defs"
if {[llength $vhd]} { if {![analyze -format vhdl $vhd]} { puts "QC_ERROR analyze (vhdl)"; exit 1 } }
if {![analyze -format sverilog -define $defs $sv]} { puts "QC_ERROR analyze"; exit 1 }
set params [qc_env QC_PARAMS]
if {$params eq ""} { set ok [elaborate $top] } else { set ok [elaborate $top -parameters $params] }
if {!$ok} { puts "QC_ERROR elaborate"; exit 1 }
current_design $top
if {![link]} { puts "QC_ERROR link"; exit 1 }

# ---- constraints
set_operating_conditions -max $::QC_OC($corner) -max_library $::QC_LIB($corner) \
                         -min $::QC_OC(ff) -min_library $::QC_LIB(ff)
qc_apply_constraints $corner
set wlm [expr {$::env(QC_TOPO) ? "topo" : [qc_wire_load $corner]}]
set_fix_hold [all_clocks]
set_clock_gating_style -sequential_cell latch -positive_edge_logic integrated -control_point before \
    -minimum_bitwidth 4 -max_fanout 32
check_design -nosplit > $out/rpt/check_design.rpt
set hook [qc_env QC_HOOK]
if {$hook ne ""} { source $hook }

# ---- compile
eval [qc_env QC_COMPILE "compile_ultra -no_autoungroup -gate_clock"]

# ---- outputs
change_names -rules verilog -hierarchy
set post [qc_env QC_POST_HOOK]                 ;# optional design-specific steps after compile + change_names (e.g. saif_map -write_map)
if {$post ne ""} { source $post }
set design [get_object_name [current_design]]
write -format ddc -hierarchy -output $out/$top.ddc
write -format verilog -hierarchy -output $out/$top.v
write_sdc $out/$top.sdc
if {$::env(QC_TOPO)} { catch {write_parasitics -output $out/$top.spef} }
report_qor                                      > $out/rpt/qor.rpt
report_area -hierarchy -nosplit                 > $out/rpt/area.rpt
report_timing -max_paths 10 -nosplit            > $out/rpt/timing_max.rpt
report_timing -delay_type min -max_paths 5 -nosplit > $out/rpt/timing_min.rpt
report_constraint -all_violators -nosplit       > $out/rpt/violators.rpt
report_clock_gating -nosplit                    > $out/rpt/clock_gating.rpt
report_power -nosplit                           > $out/rpt/power.rpt
check_timing                                    > $out/rpt/check_timing.rpt

# ---- summary (numbers only)
redirect -variable ra {report_area -nosplit}
set area NA; regexp -line {^Total cell area:\s+([0-9.]+)} $ra -> area
set nand [get_attribute [get_lib_cells $::QC_LIB($corner)/$::QC_NAND2] area]
set fh [open $out/summary.txt w]
puts $fh "design $design top $top corner $corner period_ns $::env(QC_PERIOD) topo $::env(QC_TOPO) wire_load $wlm"
puts $fh [format "cell_area_um2 %s gate_eq_kGE %.2f cells %d regs %d" $area \
    [expr {$area eq "NA" ? 0 : $area / $nand / 1000.0}] \
    [sizeof_collection [get_cells -hierarchical -filter is_hierarchical==false]] \
    [sizeof_collection [all_registers]]]
qc_put_timing $fh
puts $fh "dc_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
