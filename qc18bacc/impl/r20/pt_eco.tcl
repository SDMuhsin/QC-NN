# R20 (results/r20.md): what-if: PT sizing-only ECO (fix_eco_timing -methods size_cell, same SPEF, no re-route) on the routed act block (setup = impl/r7c/pt_blk.tcl:
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
set fh [open $dir/r20_eco_$corner.txt w]
proc w {fh tag} {
    set regs [all_registers -data_pins]; set io [add_to_collection [all_inputs] [all_outputs]]
    set p [get_timing_paths -delay_type max -max_paths 1 -exclude $io]
    set q [get_timing_paths -delay_type max -max_paths 1]
    set h [get_timing_paths -delay_type min -max_paths 1]
    puts $fh [format "%s reg2reg %.3f (%s -> %s) all %.3f (%s -> %s) hold %.3f" $tag [get_attribute $p slack] \
        [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]] [get_attribute $q slack] \
        [get_object_name [get_attribute $q startpoint]] [get_object_name [get_attribute $q endpoint]] [get_attribute $h slack]]
    flush $fh
}
w $fh before
set_app_var eco_allow_filler_cells_as_open_sites true
set m [expr {[info exists ::env(QB20_ECOM)] ? $::env(QB20_ECOM) : 0.0}]
set pm {}
if {[info exists ::env(QB20_ECOPHYS)] && $::env(QB20_ECOPHYS)} {
    # physical-aware (legal open-site) sizing: kit LEF of the run + routed DEF
    set_eco_options -physical_tech_lib_path $dir/rc/tcbn65gplus_9lmT2.lef -physical_lib_path $dir/rc/tcbn65gplus_9lmT2.lef \
        -physical_design_path $dir/out/$top.def -log_file $dir/r20_eco_phys.log \
        -filler_cell_names [get_attribute [get_lib_cells -quiet */FILL*] base_name]
    check_eco
    set pm {-physical_mode open_site}
}
puts $fh "margin $m physical [expr {$pm ne {}}]"
catch { fix_eco_timing -type setup -methods {size_cell} -setup_margin $m {*}$pm } e
catch { write_changes -format text -output $dir/r20_eco_changes_$corner.txt }
puts $fh "fix_eco_timing: [string range $e 0 200]"
w $fh after_size
redirect -variable cc { report_eco_physical_changes }
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
