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
    # hold uncertainty of this SDC (DC wrote it from QC_UNC_HOLD = common/limits.txt); the block IO budget's act_o -min hands back the same
    # U_hold (blocks/col/io_budget.tcl qb5_unc_hold, R79), so the two must agree.  Every block (R99: the check ran only
    # where the block config had already sourced the budget, the column; the regression block loads it per scenario
    # below, so its check never ran): the budget is sourced here, and a block without qb5_unc_hold fails
    set uh [expr {[regexp -line {^set_clock_uncertainty -hold ([0-9.]+)} $t -> uh] ? $uh : "none"}]
    if {[info exists P(IO_BUDGET)]} { uplevel #0 [list source $P(IO_BUDGET)] }
    if {![llength [info procs qb5_unc_hold]]} { error "qb_sdc: no qb5_unc_hold (block IO budget P(IO_BUDGET)) to check the SDC hold uncertainty $uh against" }
    if {$uh != [qb5_unc_hold]} { error "qb_sdc: SDC hold uncertainty $uh != io budget U_hold [qb5_unc_hold]" }
    # setup uncertainty of this SDC = the sign-off limit QC_UNC_SETUP (R103; before, ICC2 timed with whatever the frozen
    # DC SDC had and qb_preroute built on it, so a limit change after synthesis never reached P&R)
    set us [expr {[regexp -line {^set_clock_uncertainty -setup ([0-9.]+)} $t -> us] ? $us : "none"}]
    if {$us eq "none" || abs($us - [qb_limit QC_UNC_SETUP]) > 1e-9} { error "qb_sdc: SDC setup uncertainty $us != QC_UNC_SETUP [qb_limit QC_UNC_SETUP] (common/limits.tcl qb_limit)" }
    # the sign-off values the P&R guard-bands start from (qb_guard)
    set ::QB_SDC_HOLD_UNC $uh
    set ::QB_SDC_MAX_TRAN [expr {[regexp -line {^set_max_transition ([0-9.]+)} $t -> mt] ? $mt : "none"}]
    set out $::R/$P(TOP)_icc2.sdc
    set f [open $out w]; puts -nonewline $f $t; close $f
    qb_line "init sdc $out period $per setup_uncertainty $us hold_uncertainty $uh dc_io_delay_lines_replaced $nio"
    return $out
}
# P&R guard-bands (R92, PI decision; default 0 = none, the block .env sets them: blocks/col/col.env, blocks/rgr/rgr.env;
# sign-off itself never changes): implementation closes to
# exactly zero margin, and r91b's ECO re-route pushed untouched near-zero paths across zero ([M] 264 hold endpoints
# within 5 ps at wcl).  QC_PNR_GUARD_HOLD: ns added to the SDC hold uncertainty; QC_PNR_GUARD_TRAN: fraction f, design
# max transition = (1 - f) x the SDC's.  qb_guard applies them in the current scenario (after its SDC) and returns
# {guard_hold hold_uncertainty guard_tran max_transition} as now in force.
proc qb_guard {} {
    set gh [qc_env QC_PNR_GUARD_HOLD 0]; set gt [qc_env QC_PNR_GUARD_TRAN 0]
    if {$gh < 0 || $gt < 0 || $gt >= 1} { error "qb_guard: QC_PNR_GUARD_HOLD $gh / QC_PNR_GUARD_TRAN $gt out of range" }
    set uh $::QB_SDC_HOLD_UNC; set mt $::QB_SDC_MAX_TRAN
    if {$gh > 0} {
        set uh [expr {($uh eq "none" ? 0.0 : $uh) + $gh}]
        set_clock_uncertainty -hold $uh [all_clocks]
    }
    if {$gt > 0} {
        if {$mt eq "none"} { error "qb_guard: QC_PNR_GUARD_TRAN $gt, but the SDC has no design set_max_transition" }
        set mt [expr {(1.0 - $gt) * $mt}]
        set_max_transition $mt [current_design]
    }
    return [list $gh $uh $gt $mt]
}
# Read-back of the hold uncertainty <uh> qb_guard left (R92: measured, not echoed): the value every clock holds in every
# scenario, error unless it is <uh>.  (The design max transition reads back only once the timer runs, [M] empty on the
# init label: cts.tcl qb_cts_limits logs both per scenario.)
proc qb_guard_readback {uh} {
    set s0 [current_scenario]; set bad {}
    foreach_in_collection s [all_scenarios] {
        current_scenario $s
        set u [lsort -unique [get_attribute [all_clocks] hold_uncertainty]]
        if {[llength $u] != 1 || abs($u - $uh) > 1e-9} { lappend bad "[get_object_name $s] '$u'" }
    }
    current_scenario $s0
    if {[llength $bad]} { error "qb_guard: hold uncertainty $uh ns not held by [lrange $bad 0 2]" }
    return $u
}
# Read-back of the clock period (R107; hunt round 11 on d1978e1: block_sdc.tcl's period rewrite was never checked): the
# period of every clock in every scenario, error unless it is QB_PNR_PERIOD (common/block.sh BLK_PERIOD)
proc qb_period_readback {} {
    if {![info exists ::env(QB_PNR_PERIOD)]} { error "qb_period_readback: QB_PNR_PERIOD not set (common/block.sh)" }
    set want $::env(QB_PNR_PERIOD); set s0 [current_scenario]; set bad {}; set n 0
    foreach_in_collection s [all_scenarios] {
        current_scenario $s; incr n
        set p [lsort -unique [get_attribute [all_clocks] period]]
        if {[llength $p] != 1 || ![string is double -strict $p] || abs($p - $want) > 1e-9} { lappend bad "[get_object_name $s] '$p'" }
    }
    current_scenario $s0
    if {[llength $bad] || !$n} { error "qb_period_readback: clock period != QB_PNR_PERIOD $want in [lrange $bad 0 2] ($n scenarios)" }
    return "init clock period $want ns = QB_PNR_PERIOD (read back in $n scenarios)"
}

create_lib $::QB_LIB -technology $::QC_TF -ref_libs [list [qb_ndm]] -scale_factor $::QB_DBU
# one parasitic tech per TLU+ file (named after it), shared by the corners that use it
foreach c $::QC_SIGNOFF_CORNERS { set ptech($c) [file rootname $::QC_TLU_FILE($c)] }
foreach t [lsort -unique [lmap c $::QC_SIGNOFF_CORNERS { set ptech($c) }]] {
    read_parasitic_tech -name $t -tlup $::QC_TLU/$t.tluplus -layermap $::QC_TLU_MAP
}
set sdc [qb_sdc]
read_verilog -top $P(TOP) $P(NETLIST)
link_block
qb_flatten
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
    set gb [qb_guard]
    # hold in every scenario (R78): PrimeTime checks hold at all sign-off corners (r77 [M] pre-ECO 14 hold violators at
    # ss / ss_rcw / wcl / wcl_rcw, where ICC2 had hold off, 2 left after the ECO: pw -> u_pbw); setup by QC_ROLE
    set su [expr {$::QC_ROLE($c) eq "setup"}]
    set_scenario_status func_$c -active true -setup $su -hold true -max_transition true -max_capacitance true \
        -min_capacitance false -leakage_power false -dynamic_power false
}
lassign $gb gh uh gt mt
qb_line [qb_period_readback]
qb_line "init guard-bands QC_PNR_GUARD_HOLD $gh ns: hold uncertainty $uh ns (SDC $::QB_SDC_HOLD_UNC; read back [expr {$uh eq "none" ? "none" : [qb_guard_readback $uh]}] in [llength $::QC_SIGNOFF_CORNERS] scenarios), QC_PNR_GUARD_TRAN $gt: design max_transition $mt ns (SDC $::QB_SDC_MAX_TRAN; read back at cts)"
qb_timer
set du {}; foreach p $::QC_DONT_USE { lappend du */$p }
set_lib_cell_purpose -exclude all [get_lib_cells $du]
set_dont_use [get_lib_cells [lmap p $::QC_DONT_USE { if {[lsearch -exact [qb_hold_only] $p] >= 0} continue; string cat */ $p }]]
# hold fixing (R84): lib-cell purpose hold = exactly the shared hold-cell list (common/lib_cells.tcl qb_hold_cells, the same
# list as the PrimeTime hold ECO); the hold-only delay cells (site.tcl QC_HOLD_ONLY) have no other purpose
set_lib_cell_purpose -exclude hold [get_lib_cells */*]
set_lib_cell_purpose -include hold [get_lib_cells [lmap c [qb_hold_cells] { string cat */ $c }]]
qb_line "init hold_cells [qb_hold_cells]"
redirect -tee $::R/rpt/init_scen.rpt { report_scenarios; report_pvt }
qb_line "init corners [get_object_name [get_corners *]] modes [get_object_name [get_modes *]]"
redirect $::R/rpt/init_ptech.rpt { report_parasitic_parameters }
redirect $::R/rpt/init_check_timing.rpt { check_timing }
# IO delays as loaded (func_ss): external delay of one port per budget class, the ports P(IO_SAMPLE) of the block config
current_scenario func_ss
foreach p [expr {[info exists P(IO_SAMPLE)] ? $P(IO_SAMPLE) : {}}] {
    set dir [get_attribute [get_ports $p] direction]
    redirect -variable r { report_timing -nosplit -significant_digits 4 [expr {$dir eq "in" ? "-from" : "-to"}] [get_ports $p] }
    set k [expr {$dir eq "in" ? "input" : "output"}]
    regexp -line "$k external delay\\s+(-?\[0-9.\]+)" $r -> v
    qb_line "init io_delay $p $k [expr {[info exists v] ? $v : "NA"}]"; unset -nocomplain v
}
qb_qor init
qb_done init 1
