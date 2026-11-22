# G1 + design setup: design library on the ICC2 tech file + the standard-cell NDM, TLU+ per corner (kit layer map),
# netlist, MCMM (one mode, corners tt / ss / ff = site.tcl QC_LIB / QC_OC), P&R SDC -> block label init.
#   SDC: common/block_sdc.tcl (DC SDC without the per-net estimates, period QB_PNR_PERIOD) + the block IO budget
#   (P(IO_BUDGET), qb5_io_lines at that period) in place of DC's IO delays (block_sdc's IO rescale does not match DC's
#   "-clock qb_clk  -max" lines); ICC2 picks each corner's library by operating condition, so DC's
#   set_operating_conditions and the -library of set_driving_cell are dropped.  Written to <run>/<top>_icc2.sdc.
#   Scenarios: ss setup, tt + ff hold, max transition / capacitance everywhere.
source [file dirname [info script]]/common.tcl
array set ::QB_SCEN {ss {setup 1 hold 0} tt {setup 0 hold 1} ff {setup 0 hold 1}}

proc qb_sdc {} {
    global P
    set ::env(QC_PNR_OUT) $::R
    source $::QBF/common/block_sdc.tcl
    set f [open $P(SDC)]; set t [read $f]; close $f
    regexp -line {^create_clock .*-period ([0-9.]+)} $t -> per
    regsub -all -line {^set_operating_conditions .*$} $t {} t
    regsub -all {(set_driving_cell [^\[]*)-library \S+ } $t {\1} t
    set nio 0
    if {[info exists P(IO_BUDGET)]} {
        set nio [regsub -all -line {^set_(input|output)_delay .*$} $t {} t]
        source $P(IO_BUDGET)
        append t "\n# IO budget [file tail $P(IO_BUDGET)], period $per\n[qb5_io_lines $per]\n"
    }
    set out $::R/$P(TOP)_icc2.sdc
    set f [open $out w]; puts -nonewline $f $t; close $f
    qb_line "init sdc $out period $per dc_io_delay_lines_replaced $nio"
    return $out
}

create_lib $::QB_LIB -technology $::QC_TF -ref_libs [list $::QB_NDM]
foreach c $::QC_CORNERS {
    read_parasitic_tech -name $c -tlup $::QC_TLU/$::QC_TLU_FILE($c) -layermap $::QC_TLU_MAP
}
set sdc [qb_sdc]
read_verilog -top $P(TOP) $P(NETLIST)
link_block

create_mode func
foreach c $::QC_CORNERS {
    create_corner $c
    create_scenario -name func_$c -mode func -corner $c
}
foreach c $::QC_CORNERS {
    current_scenario func_$c
    set_operating_conditions $::QC_OC($c)
    set_parasitic_parameters -early_spec $c -late_spec $c
    source $sdc
    array set s $::QB_SCEN($c)
    set_scenario_status func_$c -active true -setup $s(setup) -hold $s(hold) -max_transition true -max_capacitance true \
        -min_capacitance false -leakage_power false -dynamic_power false
}
set du {}; foreach p $::QC_PNR_DONT_USE { lappend du */$p }
set_lib_cell_purpose -exclude all [get_lib_cells $du]
redirect -tee $::R/rpt/init_scen.rpt { report_scenarios; report_pvt }
redirect $::R/rpt/init_ptech.rpt { report_parasitic_parameters }
redirect $::R/rpt/init_check_timing.rpt { check_timing }
# IO delays as loaded (func_ss): external delay of one port per budget class
current_scenario func_ss
foreach p {act[0] cd[0] pf[0] act_o[0] f_y[0]} {
    set dir [get_attribute [get_ports $p] direction]
    redirect -variable r { report_timing -nosplit [expr {$dir eq "in" ? "-from" : "-to"}] [get_ports $p] }
    set k [expr {$dir eq "in" ? "input" : "output"}]
    regexp -line "$k external delay\\s+(-?\[0-9.\]+)" $r -> v
    qb_line "init io_delay $p $k [expr {[info exists v] ? $v : "NA"}]"; unset -nocomplain v
}
qb_qor init
qb_done init 1
