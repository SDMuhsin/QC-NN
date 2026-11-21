# R45 diagnosis of the column tt ETM outlier arcs (act[2911] fall setup +0.78 .. -8.81 ns vs ~-0.86 on its neighbours):
# same session as impl/r5a/etm.tcl (routed netlist, def2spef SPEF, propagated clock), then the port -> D path of an
# outlier and a normal pin with the driving cell's input transition swept over the ETM index.  env R45_PINS, R45_SLEWS.
source $::env(QC_FLOW)/common/lib.tcl
set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT); set top $::env(QC_TOP)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner]]
read_verilog $dir/out/$top.v
current_design $top
link_design
qc_apply_constraints $corner
set_propagated_clock [all_clocks]
read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef
update_timing
foreach p $::env(R45_PINS) {
    foreach s $::env(R45_SLEWS) {
        set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $::QC_LIB($corner) -pin [lindex $::QC_DRV_IN 1] \
            -input_transition_rise $s -input_transition_fall $s [get_ports $p]
        foreach dt {max min} {
            puts "R45_PATH $p slew $s $dt"
            report_timing -fall_from [get_ports $p] -delay_type $dt -input_pins -transition_time -capacitance -nets \
                -path_type full_clock_expanded -significant_digits 4
        }
    }
    set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $::QC_LIB($corner) -pin [lindex $::QC_DRV_IN 1] [get_ports $p]
    foreach_in_collection l [get_pins -of [get_nets -of [get_ports $p]] -filter "direction==in"] {
        catch { report_delay_calculation -from [get_ports $p] -to $l -fall } e; puts $e
    }
}
exit
