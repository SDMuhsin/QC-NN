# G1 + design setup: design library on the ICC2 tech file + the standard-cell NDM, TLU+ per corner (kit layer map),
# netlist, MCMM (one mode, one scenario func_<c> per sign-off corner c of the site.tcl corner table: QC_SIGNOFF_CORNERS,
# library by QC_OC, TLU+ QC_TLU_FILE, role QC_ROLE setup or hold), P&R SDC -> block label init.
#   SDC: common/block_sdc.tcl (DC SDC without the per-net estimates, period QB_PNR_PERIOD) + the block IO budget
#   (P(IO_BUDGET), qb5_io_apply at that period per scenario: the min input delay is the corner's library clock -> Q, R77)
#   in place of DC's IO delays (block_sdc's IO rescale does not match DC's
#   "-clock qb_clk  -max" lines); ICC2 picks each corner's library by operating condition, so DC's
#   set_operating_conditions and the -library of set_driving_cell are dropped.  Written to <run>/<top>_icc2.sdc.
#   Scenarios: setup by QC_ROLE (R68: setup wc / wcl x Cworst / RCworst), hold in every scenario (R78; was hold lt / ml x Cbest / RCbest + tc only),
#   max transition / capacitance everywhere.
source [file dirname [info script]]/common.tcl

proc qb_sdc {} {
    global P
    set ::env(QC_PNR_OUT) $::R
    source $::QBF/common/block_sdc.tcl
    set f [open $P(SDC)]; set t [read $f]; close $f
    regexp -line {^create_clock .*-period ([0-9.]+)} $t -> per
    regsub -all -line {^set_operating_conditions .*\n} $t {} t
    regsub -all {(set_driving_cell [^\[]*)-library \S+ } $t {\1} t
    set nio 0
    if {[info exists P(IO_BUDGET)]} { set nio [regsub -all -line {^set_(input|output)_delay .*\n} $t {} t] }
    set ::QB_PNR_PER $per
    set out $::R/$P(TOP)_icc2.sdc
    set f [open $out w]; puts -nonewline $f $t; close $f
    qb_line "init sdc $out period $per dc_io_delay_lines_replaced $nio"
    return $out
}

create_lib $::QB_LIB -technology $::QC_TF -ref_libs [list $::QB_NDM] -scale_factor $::QB_DBU
# one parasitic tech per TLU+ file (named after it), shared by the corners that use it
foreach c $::QC_SIGNOFF_CORNERS { set ptech($c) [file rootname $::QC_TLU_FILE($c)] }
foreach t [lsort -unique [lmap c $::QC_SIGNOFF_CORNERS { set ptech($c) }]] {
    read_parasitic_tech -name $t -tlup $::QC_TLU/$t.tluplus -layermap $::QC_TLU_MAP
}
set sdc [qb_sdc]
read_verilog -top $P(TOP) $P(NETLIST)
link_block
qb_timer
# feedthrough buffers (P(FEEDTHRU): output ports each driven by one netlist buffer from an input port, e.g. the column's
# act -> act_o, which the abutted chip relies on to re-buffer act).  R68 (PI decision): every one sized to the one lib cell
# P(FEEDTHRU_CELL) and dont_touch, and its net to the port dont_touch (no re-buffering), so the port's driver is exactly
# that cell in every abutted copy, i.e. the driving cell the block's own SDC gives the matching input port (column:
# blocks/col/io_budget.tcl QB5_FT), and optimisation can neither remove (R59: place_opt removed all 4608 free buffers,
# netlist assign act_o = act, LVS merged the ports) nor resize it (R67: ICC2 resized size_only drivers after the
# driving-cell model read them; PrimeTime then needed 4 setup ECO rounds).
if {[info exists P(FEEDTHRU)]} {
    set ftp [get_ports $P(FEEDTHRU)]
    set ftn [get_nets -of_objects $ftp]
    set ft [get_cells -of_objects [get_pins -of_objects $ftn -filter "direction==out"]]
    if {[sizeof_collection $ft] != [sizeof_collection $ftp]} { error "QB feedthrough: [sizeof_collection $ft] driver cells for [sizeof_collection $ftp] ports" }
    set r0 [lsort -unique [get_attribute $ft ref_name]]
    size_cell $ft -lib_cell [index_collection [get_lib_cells */$P(FEEDTHRU_CELL)] 0]
    set_dont_touch $ft true
    set_dont_touch $ftn true
    qb_line "init feedthrough cells [sizeof_collection $ft] ports [sizeof_collection $ftp] ($P(FEEDTHRU)) [join $r0 /] -> [lsort -unique [get_attribute $ft ref_name]], dont_touch cells + port nets"
}

create_mode func
foreach c $::QC_SIGNOFF_CORNERS {
    create_corner $c
    create_scenario -name func_$c -mode func -corner $c
}
# the corner "default" that the new block brings (no scenario, no parasitic tech: R68 NEX-018 "no valid parasitic for
# default corner" on every extraction, 40 in route, 872 in place) is not a sign-off corner (R71)
set dc [get_corners -quiet default]
if {[sizeof_collection $dc]} { remove_corners $dc }
foreach c $::QC_SIGNOFF_CORNERS {
    current_scenario func_$c
    set_operating_conditions $::QC_OC($c)
    set_parasitic_parameters -early_spec $ptech($c) -late_spec $ptech($c)
    source $sdc
    # IO budget of this corner (ideal clock: no arrival shift; min input delay = the corner's library clock -> Q)
    if {[info exists P(IO_BUDGET)]} { source $P(IO_BUDGET); qb5_io_apply $::QB_PNR_PER 0.0 0.0 [qb_lib_tcq $c] }
    # hold in every scenario (R78): PrimeTime checks hold at all sign-off corners (r77 [M] pre-ECO 14 hold violators at
    # ss / ss_rcw / wcl / wcl_rcw, where ICC2 had hold off, 2 left after the ECO: pw -> u_pbw); setup by QC_ROLE
    set su [expr {$::QC_ROLE($c) eq "setup"}]
    set_scenario_status func_$c -active true -setup $su -hold true -max_transition true -max_capacitance true \
        -min_capacitance false -leakage_power false -dynamic_power false
}
qb_timer
set du {}; foreach p $::QC_DONT_USE { lappend du */$p }
set_lib_cell_purpose -exclude all [get_lib_cells $du]
set_dont_use [get_lib_cells $du]
redirect -tee $::R/rpt/init_scen.rpt { report_scenarios; report_pvt }
qb_line "init corners [get_object_name [get_corners *]] modes [get_object_name [get_modes *]]"
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
