# Shared Tcl of every ICC2 step (flow/icc2/<step>.tcl; run by common/env.sh qb_icc2 from blocks/<b>/run.sh).
# Environment: QC_FLOW (flow/tsmc65, set by its common/tool.sh), QB_ICC2_CFG (block config, e.g. blocks/col/icc2.cfg),
#   QB_ICC2_RUN (run dir: <run>/<top>.nlib design library, rpt/, out/), QC_BUILD, QB_ICC2_CORES (default 16).
# Kit facts come from the flow/tsmc65 site files (site.tcl: libraries, tf, TLU+; site/pnr.tcl: LEF, GDS, cells, layers).
#   ::QB_NDM            standard-cell NDM (flow/icc2/libs.tcl), shared by every block under $QC_BUILD/icc2/ndm
#   qb_open <from> <to> open the design library, copy block label <from> to <to> (from = to: reopen it), make it current,
#                       qb_timer
#   qb_timer            timer options of every design step: CCS receiver capacitance in delay / slew / max_cap
#                       (time.enable_ccs_rcv_cap, default false: ICC2 then loads nets with the NLDM pin cap while
#                       PrimeTime uses the CCS receiver model of the same _ccs.db, R55: 0.06 vs 0.09 pF on n1690)
#                       and crosstalk (time.si_enable_analysis, default false; R59 route_opt ran without SI, ROPT-002,
#                       and the SPEF had no coupling capacitance): SI delta delays in route_opt / eco timing, extraction
#                       keeps the coupling capacitances, so outputs.tcl writes a coupled SPEF (PT sign-off runs SI too);
#                       the OCV derate of common/derate.tcl (late 1.05 / early 0.95) on every scenario
#   qb_done <step> [as] save (as 1: save the current block as label <step>, the init step), log the step end in
#                       <run>/summary.txt, QB_ICC2_DONE marker for the wrapper
#   qb_io_load          IO loads that depend on the block's own layout: P(IO_LOAD) = {measure apply} procs of P(IO_BUDGET)
#                       (column: blocks/col/io_budget.tcl qb5_act_o_caps / qb5_act_o_load, act_o[b] = own act[b] net),
#                       called per scenario on the current timing (placement estimate or routed); cts.tcl, route.tcl;
#                       it first re-applies qb_io_drive (optimisation resizes the feedthroughs)
#   qb_io_drive         input driving cells that depend on the block's own netlist: P(IO_DRIVE) = {measure apply} procs
#                       of P(IO_BUDGET) (column: qb5_act_drv / qb5_act_drv_apply, act[b] driven by the lib cell of the
#                       block's own act_o[b] driver), applied in every scenario; init.tcl (after the SDC), qb_io_load
#   qb_qor <step>       QoR lines (cells, utilization, DRV count, WNS / TNS / NVE per scenario) + rpt/<step>_{qor,drv}.rpt
#   qb_line <text>      append a line to <run>/summary.txt (and the log)
#   qb_antenna_rules    kit antenna rules (route / eco via qb_route_setup, abstract.tcl)
#   qb_route_setup      routing options of route.tcl / eco.tcl: kit antenna rules, antenna-aware detail routing with
#                       ANTENNA diodes, port nets checked with a minimum outside gate (no ZRT-311), timing-driven
#                       global / track / detail routing
#   qb_fillers          decap (DCAP*, removed where they violate) then metal-free FILL* cells in every empty site
#   qb_route_checks <step>  check_routes / check_lvs -> rpt/<step>_check_{routes,lvs}.rpt + summary lines
#   qb_pg_check <step>  PG pin gate (R67; floorplan.tcl, abstract.tcl): the VDD / VSS terminals are exactly the straps of
#                       the chip PG grid's pin layer (floorplan/pg_grid.tcl ::QB_PG_PIN): that layer only, strap width,
#                       each across the whole die, low edges = qb_pg_expect of the core (VSS at core + offset, VDD at
#                       + pitch / 2, pitch); error otherwise, one summary line
set ::QBF [file normalize [file dirname [info script]]/..]
set ::QC_BUILD $::env(QC_BUILD)
source $::env(QC_FLOW)/common/lib.tcl
source $::env(QC_FLOW)/site/pnr.tcl
source $::env(QB_ICC2_CFG)
set ::R $::env(QB_ICC2_RUN)
set ::QB_NDM $::QC_BUILD/icc2/ndm/[file rootname [file tail $::QC_PNR_LEF]].ndm
set ::QB_LIB $::R/$P(TOP).nlib
file mkdir $::R/rpt $::R/out
if {[info commands set_host_options] ne ""} { set_host_options -max_cores [qc_env QB_ICC2_CORES 16] }

proc qb_line {t} {
    puts "QB_ICC2 $t"
    set f [open $::R/summary.txt a]; puts $f $t; close $f
}
proc qb_open {from to} {
    global P
    open_lib $::QB_LIB
    # (open_lib opens no block: from = to needs open_block, R60; copy_block leaves the copy open)
    if {$from ne $to} { copy_block -from_block $P(TOP)/$from -to_block $P(TOP)/$to -force; current_block $P(TOP)/$to } \
    else { open_block $P(TOP)/$to }
    link_block
    qb_timer
}
source $::QBF/common/derate.tcl
source $::QBF/floorplan/pg_grid.tcl
proc qb_timer {} {
    set_app_options -name time.enable_ccs_rcv_cap -value true
    set_app_options -name time.si_enable_analysis -value true
    # OCV derate (common/derate.tcl) on every scenario's corner (none yet in init before create_scenario: init.tcl
    # calls qb_timer again after them)
    if {![sizeof_collection [get_scenarios -quiet]]} return
    set s0 [current_scenario]
    foreach_in_collection s [get_scenarios] { current_scenario $s; qb_derate }
    current_scenario $s0
}
proc qb_io_load {} {
    global P
    if {![info exists P(IO_LOAD)]} return
    lassign $P(IO_LOAD) measure apply
    source $P(IO_BUDGET)
    qb_io_drive
    update_timing
    set s0 [current_scenario]
    # every scenario measured before the first set_load (it invalidates the timing and clears the net parasitics)
    foreach_in_collection s [get_scenarios] {
        current_scenario $s
        # port max_rise_load_cap of an input port = its net's pin + wire capacitance (R64 [M]: = PrimeTime's net
        # total_capacitance_max on the routed r62 block, 0.067407 pF act[0] ss)
        set m([get_object_name $s]) [$measure {apply {p {get_attribute $p max_rise_load_cap}}}]
    }
    foreach_in_collection s [get_scenarios] {
        current_scenario $s
        redirect -variable r { $apply $m([get_object_name $s]) }
        qb_line "io_load [get_object_name $s]: [lindex [regexp -inline -line {QB.*_LOAD.*$} $r] 0]"
    }
    current_scenario $s0
}
proc qb_io_drive {} {
    global P
    if {![info exists P(IO_DRIVE)]} return
    lassign $P(IO_DRIVE) measure apply
    source $P(IO_BUDGET)
    set d [$measure]
    set s0 [current_scenario]
    foreach_in_collection s [get_scenarios] { current_scenario $s; redirect -variable r { $apply $d } }
    current_scenario $s0
    qb_line "io_drive: [lindex [regexp -inline -line {QB.*_DRV.*$} $r] 0]"
}
# one QoR line: setup WNS / TNS / violators per scenario, hold WNS per scenario, DRV counts, utilization
proc qb_qor {step} {
    redirect -variable q { report_qor -summary -nosplit }
    redirect $::R/rpt/${step}_qor.rpt { report_qor -summary -nosplit }
    redirect -variable c { report_constraints -all_violators -max_transition -max_capacitance -scenarios [all_scenarios] -nosplit }
    redirect $::R/rpt/${step}_drv.rpt { puts $c }
    if {[catch { redirect -variable ru { report_utilization }; regexp {Utilization Ratio:\s*([0-9.]+)} $ru -> u }] || ![info exists u]} { set u NA }
    qb_line "$step [clock format [clock seconds] -format %T -gmt 1] cells [sizeof_collection [get_flat_cells]] util $u drv_violations [expr {[regexp {Total number of violation\(s\):\s*(\d+)} $c -> n] ? $n : "NA"}]"
    foreach l [split $q "\n"] { if {[regexp {\((Setup|Hold)\)|^\s*Context} $l]} { qb_line "  $l" } }
}
proc qb_done {step {as 0}} {
    global P
    if {$as} { save_block -as $P(TOP)/$step } else { save_block }
    save_lib
    qb_line "$step done [clock format [clock seconds] -format %T -gmt 1]"
    puts "QB_ICC2_DONE $step"
}
# kit antenna rules (Milkyway clf antennaRule_n65_<n>lm.tcl): the file is ICC1 Tcl, so the Milkyway library argument and
# its set_parameter / current_mw_lib / report lines are dropped; they are not stored with the block (R67 [M]: none in a
# reopened library), so every step that needs them loads them (qb_route_setup, abstract.tcl)
proc qb_antenna_rules {} {
    set nm [regexp -inline {[0-9]+lm} [file tail $::QC_TF]]
    set fh [open $::QC_MW/clf/antennaRule_n65_$nm.tcl]; set t [read $fh]; close $fh
    regsub -all -line {^\s*(set_parameter|set lib|remove_antenna_rules|report_antenna_rules).*$} $t {} t
    regsub -all {(define_antenna_(?:layer_)?rule)\s+\$lib} $t {\1} t
    uplevel #0 $t
    redirect $::R/rpt/antenna_rules.rpt { report_antenna_rules }
}
# port nets (R67): Zroute skips the antenna check of a port net whose outside gate is unknown (route.detail.
# default_port_external_gate_size -1: ZRT-311 on the cd / clk / rst_n port nets of r65), so the port's outside is one
# gate of the smallest gate area of the cell LEF (the most conservative ratio: area / gate) and no outside diode
# (port_antenna_mode float, the default); the top-side metal is the top router's, from the abstract's PARTIAL data
proc qb_route_setup {} {
    qb_antenna_rules
    set fh [open $::QC_PNR_LEF]; set l [read $fh]; close $fh
    set g {}; foreach {- v} [regexp -all -inline {ANTENNAGATEAREA\s+([0-9.eE+-]+)} $l] { if {$v > 0} { lappend g $v } }
    set gmin [tcl::mathfunc::min {*}$g]
    set_app_options -name route.detail.default_port_external_gate_size -value $gmin
    qb_line "route_setup port external gate size $gmin (min ANTENNAGATEAREA of [llength $g] cell-LEF values)"
    set_app_options -name route.detail.antenna -value true
    set_app_options -name route.detail.insert_diodes_during_routing -value true
    set_app_options -name route.detail.diode_libcell_names -value [lindex $::QC_PNR_DIODE 0]
    foreach o {route.global.timing_driven route.track.timing_driven route.detail.timing_driven} { set_app_options -name $o -value true }
}
# decaps (they carry M1) first and removed where they violate, then the metal-free FILL* close every remaining gap
# (R54 ran both in one create_stdcell_fillers: the removed DCAPs left empty gaps, Calibre NW.S.1 / OD2.S.5 27 004)
proc qb_fillers {} {
    foreach {lc chk} [list $::QC_PNR_DCAP 1 $::QC_PNR_FILL 0] {
        set fl {}; foreach c $lc { lappend fl */$c }
        create_stdcell_fillers -lib_cells [get_lib_cells $fl]
        connect_pg_net -automatic
        if {$chk} { remove_stdcell_fillers_with_violation }
    }
}
proc qb_route_checks {step} {
    redirect $::R/rpt/${step}_check_routes.rpt { check_routes }
    redirect $::R/rpt/${step}_check_lvs.rpt { check_lvs -max_errors 0 }
    foreach r {check_routes check_lvs} {
        set t [exec cat $::R/rpt/${step}_$r.rpt]
        foreach l [split $t "\n"] { if {[regexp -nocase {total number|total.*(error|violation)|open|short} $l]} { qb_line "$step $r [string trim $l]" } }
    }
}
proc qb_pg_check {step} {
    lassign [qb_pg_strap $::QB_PG_PIN] dir w pitch off
    lassign [get_attribute [current_block] boundary_bbox] d0 d1
    lassign [get_attribute [get_core_area] bbox] c0 c1
    set bad {}
    foreach net {VSS VDD} {
        set ys {}
        foreach_in_collection t [get_terminals -quiet -of_objects [get_ports $net]] {
            lassign [get_attribute $t bbox] p0 p1
            set ly [get_attribute $t layer.name]
            if {$ly ne $::QB_PG_PIN || abs([lindex $p1 1] - [lindex $p0 1] - $w) > 1e-6
                || abs([lindex $p0 0] - [lindex $d0 0]) > 1e-6 || abs([lindex $p1 0] - [lindex $d1 0]) > 1e-6} {
                lappend bad "$net:$ly:[list $p0 $p1]"; continue
            }
            lappend ys [format %.3f [lindex $p0 1]]
        }
        set ys [lsort -real $ys]
        set ex [qb_pg_expect $::QB_PG_PIN $net [lindex $c0 1] [lindex $c1 1]]
        if {$ys ne $ex} { lappend bad "$net y [lrange $ys 0 2].. ([llength $ys]) vs [lrange $ex 0 2].. ([llength $ex])" }
        set n($net) [llength $ys]
    }
    qb_line "$step pg_pins [expr {[llength $bad] ? "FAIL" : "ok"}] layer $::QB_PG_PIN w $w pitch $pitch VSS $n(VSS) from [format %.3f [expr {[lindex $c0 1] + $off}]] VDD $n(VDD) from [format %.3f [expr {[lindex $c0 1] + $off + $pitch / 2.0}]] bad [llength $bad] [lrange $bad 0 3]"
    if {[llength $bad]} { error "QB PG pins off the chip grid: [lrange $bad 0 3]" }
}
