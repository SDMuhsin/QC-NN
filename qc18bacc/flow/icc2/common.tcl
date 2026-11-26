# Shared Tcl of every ICC2 step (flow/icc2/<step>.tcl; run by common/env.sh qb_icc2 from blocks/<b>/run.sh).
# Environment: QC_FLOW (flow/tsmc65, set by its common/tool.sh), QB_ICC2_CFG (block config, e.g. blocks/col/icc2.cfg),
#   QB_ICC2_RUN (run dir: <run>/<top>.nlib design library, rpt/, out/), QC_BUILD, QB_ICC2_CORES (default 16).
# Kit facts come from the flow/tsmc65 site files (site.tcl: libraries, tf, TLU+; site/pnr.tcl: LEF, GDS, cells, layers).
#   ::QB_DBU            database units / um = the tech file's lengthPrecision (NDM, design library, GDS; R77)
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
#   qb_done <step> [as] dont_use gate (common/lib_cells.tcl qb_dont_use_gate, R77: no QC_DONT_USE lib cell usable, no
#                       instance of one), save (as 1: save the current block as label <step>, the init step), log the
#                       step end in <run>/summary.txt, QB_ICC2_DONE marker for the wrapper
#   qb_io_load          IO loads that depend on the block's own layout: P(IO_LOAD) = {measure apply} procs of P(IO_BUDGET)
#                       (column: blocks/col/io_budget.tcl qb5_act_o_caps / qb5_act_o_load, act_o[b] = own act[b] net),
#                       called per scenario on the current timing (placement estimate or routed); cts.tcl, route.tcl;
#                       then P(IO_TRAN) = {measure apply diff} input transitions from the block's own outputs (column:
#                       act[b] = own act_o[b] transition, R71), two measure / apply rounds, residual logged
#   qb_io_lat <step>    compute_clock_latency (I/O latency = median sink latency, derated per check: R77, below) + log
#   qb_qor <step>       QoR lines (cells, utilization, DRV count, WNS / TNS / NVE per scenario) + rpt/<step>_{qor,drv}.rpt
#   qb_line <text>      append a line to <run>/summary.txt (and the log)
#   qb_antenna_rules    kit antenna rules (route / eco via qb_route_setup, abstract.tcl)
#   qb_route_setup      routing options of route.tcl / eco.tcl: kit antenna rules, antenna-aware detail routing with
#                       ANTENNA diodes, port nets checked with a minimum outside gate (no ZRT-311), timing-driven
#                       global / track / detail routing, redundant via insertion after every detail route (R71)
#   qb_feedthru_ndr     feedthrough port nets P(FEEDTHRU) on a spacing NDR P(FEEDTHRU_NDR) (R74, route.tcl)
#   qb_fillers          decap (DCAP*, removed where they violate) then metal-free FILL* cells in every empty site
#   qb_route_checks <step>  check_routes / check_lvs -> rpt/<step>_check_{routes,lvs}.rpt + summary lines
#   qb_hold_reserve     netlist-targeted hold-cell reservation (R87, P(HOLD_RESERVE); place.tcl)
#   qb_isolate_ports    input-port isolation buffers by ICC2 set_isolate_ports (R88, P(ISOLATE); place.tcl before place_opt)
#   qb_isolate_magnet   isolation buffers pulled to their port terminals (magnet_placement, legalize_only; place.tcl)
#   qb_isolate_report <step>  isolation gate (each loaded P(ISOLATE) port drives exactly one buffer) + count / area / stub
#   qb_flatten          logical hierarchy flattened at init (R91, ungroup_cells -all -flatten; init.tcl) + gate
#   qb_eco_names <chg>  PT change-list gate (R89 / R91, eco.tcl): every cell / net / pin / port the change list names
#                       exists, lib cells applied, every new cell = PT's new-cell record (lib cell, load pins); counts +
#                       rpt/eco_names.rpt
#   qb_pg_check <step>  PG pin gate (R67; floorplan.tcl, abstract.tcl): the VDD / VSS terminals are exactly the straps of
#                       the chip PG grid's pin layer (floorplan/pg_grid.tcl ::QB_PG_PIN): that layer only, strap width,
#                       each across the whole die, low edges = qb_pg_expect of the core (VSS at core + offset, VDD at
#                       + pitch / 2, pitch); error otherwise, one summary line
set ::QBF [file normalize [file dirname [info script]]/..]
set ::QC_BUILD $::env(QC_BUILD)
source $::env(QC_FLOW)/common/lib.tcl
source $::env(QC_FLOW)/site/pnr.tcl
source $::QBF/common/lib_cells.tcl
source $::QBF/common/eco_changes.tcl
source $::env(QB_ICC2_CFG)
set ::R $::env(QB_ICC2_RUN)
# database unit (R77): the tech file's lengthPrecision (tsmcn65_9lmT2.tf: 1000 / um, the kit's "1nm as layout database
# unit" guideline, CLN65GP DR TN65CLDR001 3.7.1.1, and the Calibre decks' PRECISION 1000) for the NDM (libs.tcl), the
# design library (init.tcl) and the GDS (outputs.tcl).  Before R77 the NDM took ICC2's default 10000, the design library
# followed it, and write_gds -units 1000 warned of lost precision (LIB-058).  The NDM name carries it (the 10000 NDM of
# earlier runs stays readable for their libraries).
set _h [open $::QC_TF]; regexp {lengthPrecision\s*=\s*(\d+)} [read $_h] -> ::QB_DBU; close $_h
set ::QB_NDM $::QC_BUILD/icc2/ndm/[file rootname [file tail $::QC_PNR_LEF]]_dbu$::QB_DBU.ndm
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
    # input transitions measured on the block's own outputs (P(IO_TRAN) = {measure apply diff}; column: act[b] = own
    # act_o[b] transition, io_budget.tcl qb5_act_tran*), after the loads: every scenario measured, then applied; the second
    # round logs how far the first moved them (PrimeTime iterates to its fixed point at sign-off, col_blk.tcl)
    if {[info exists P(IO_TRAN)]} {
        lassign $P(IO_TRAN) tmeasure tapply tdiff
        foreach i {1 2} {
            update_timing
            foreach_in_collection s [get_scenarios] { current_scenario $s; set t([get_object_name $s]) [$tmeasure] }
            set d 0.0
            foreach_in_collection s [get_scenarios] {
                set n [get_object_name $s]; current_scenario $s
                if {[info exists t0($n)]} { set d [expr {max($d, [$tdiff $t0($n) $t($n)])}] }
                redirect -variable r { $tapply $t($n) }
                qb_line "io_tran $i $n: [lindex [regexp -inline -line {QB.*_TRAN .*$} $r] 0]"
            }
            if {$i > 1} { qb_line [format "io_tran residual %.5f ns (round 2 vs 1, max over scenarios)" $d] }
            array set t0 [array get t]
        }
    }
    current_scenario $s0
}
# IO latency of the propagated clock (cts.tcl, route.tcl): compute_clock_latency sets the I/O ports' ideal clock latency
# to the sinks' median latency, and ICC2 derates it per check like any clock path (R77 [M] r75 route label, func_ss
# act[739] -> act_o[739]: launch 0.74 = late, capture 0.66 = early, vs PrimeTime's p50 late / early register clock
# arrival 0.737 / ~0.667): input -max + late, output -max - early, input -min + early, output -min - late, which
# PrimeTime applies explicitly (signoff/pt/col_blk.tcl, blocks/col/io_budget.tcl).  qb_io_lat <step>: compute_clock_latency
# + one line per IO side of that latency (launch / capture, setup and hold scenario).  Then P(IO_MIN) = {measure apply}
# (column: blocks/col/io_budget.tcl qb5_act_o_lat_icc2 / qb5_act_o_min_icc2, R78): every hold scenario func_<c> measured,
# then each applied with Tq = qb_lib_tcq <c>: output -min
# constraints measured on this latency (column: act_o -min = capture latency - (early latency + Tq)).
proc qb_io_lat {step} {
    global P
    # (R85, PI decision 2) the register set and value per corner logged: "io pair regs" is the one IO latency definition,
    # PrimeTime measures the same set (signoff/pt/io_lat.tcl qb_io_reg_clock_pins)
    redirect -variable ccl { compute_clock_latency -verbose }
    foreach {- e l c u n} [regexp -all -inline -line {^\S+\s+Yes\s+([0-9.]+)\s+[0-9.]+\s+([0-9.]+)\s+[0-9.]+\s+(\S+)\s+\S+\s+\S+\s+(.*?)[ \t]+(\d+)[ \t]*$} $ccl] {
        qb_line "io_lat $step ccl $c early $e late $l using '$u' regs $n"
    }
    set s0 [current_scenario]
    if {[info exists P(IO_MIN)]} {
        lassign $P(IO_MIN) measure apply
        set hs [get_scenarios -filter hold==true]
        foreach_in_collection sc $hs { current_scenario $sc; set m([get_object_name $sc]) [$measure] }
        foreach_in_collection sc $hs {
            current_scenario $sc; set n [get_object_name $sc]
            qb_line "io_min $step $n [$apply $m($n) [qb_lib_tcq [regsub {^func_} $n {}]]]"
        }
    }
    foreach sc [list [lindex [get_object_name [get_scenarios -filter setup==true]] 0] [lindex [get_object_name [get_scenarios -filter hold==true]] 0]] dt {max min} {
        current_scenario $sc
        redirect -variable r { report_timing -nosplit -delay_type $dt -scenarios $sc -from [get_ports {act[0]}] -to [get_ports {act_o[0]}] }
        set v [lmap {- x} [regexp -all -inline -line {^\s*clock network delay \((?:ideal|propagated)\)\s+(-?[0-9.]+)} $r] { set x }]
        qb_line "io_lat $step $sc $dt act\[0\] -> act_o\[0\] clock network delay launch / capture $v"
    }
    current_scenario $s0
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
    qb_line [qb_dont_use_gate $step 1]
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
    # crosstalk at route time (R74; Synopsys RM route settings, needs time.si_enable_analysis of qb_timer): crosstalk-
    # driven global routing and track assignment (default false: Q-2019.12 has no detail-route counterpart).  R73 [M]: the
    # noise victims PrimeTime cannot fix (act_o feedthroughs dont_touch, u_acc U123/A2 650 um driver-to-load-cluster nets)
    # came out of a crosstalk-blind route.  (route_opt.flow.xtalk_reduction is deprecated in Q-2019.12, NDMUI-443, and
    # ran no crosstalk phase in r74 [M]: not set, R75.)
    foreach o {route.global.crosstalk_driven route.track.crosstalk_driven} { set_app_options -name $o -value true }
    # redundant vias (R71; Synopsys RM route settings): every detail route (route_auto, route_opt's ECO routing, route_eco)
    # ends with redundant via insertion at medium effort (single-cut vias -> 2-cut arrays where DRC-clean; no
    # add_via_mapping, the tool's default mapping).  R68 [M] without it: double-via rate 0.38 % (route.log).
    set_app_options -name route.common.post_detail_route_redundant_via_insertion -value medium
}
# feedthrough port nets (P(FEEDTHRU), dont_touch since init) routed with spacing multiplier P(FEEDTHRU_NDR) (R74; route.tcl
# before route_auto).  dont_touch keeps the cell and net out of optimisation (no buffering / sizing), not out of routing,
# so the router can still space them; PrimeTime cannot fix their noise (reason V), so it must not be routed in.
proc qb_feedthru_ndr {} {
    global P
    if {![info exists P(FEEDTHRU_NDR)]} return
    set n [get_nets -of_objects [get_ports $P(FEEDTHRU)]]
    create_routing_rule qb_feedthru -default_reference_rule -multiplier_spacing $P(FEEDTHRU_NDR)
    set_routing_rule $n -rule qb_feedthru
    qb_line "route feedthrough NDR qb_feedthru (spacing x $P(FEEDTHRU_NDR)) on [sizeof_collection $n] nets ($P(FEEDTHRU))"
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
# Netlist-targeted hold-cell reservation (R87, PI decision; place.tcl before place_opt, enabled per block by
# P(HOLD_RESERVE) = the input-port globs, column: pw / pf / w_ld).
# Why [M] (R80-R86): the direct port -> AO22 -> flop paths of the pin-adjacent register banks each need about one hold
# cell; r84 left 37 PT-unfixable (reason D) hold endpoints pw / w_ld -> u_pbw in a 100 %-full window (R86, exact bbox
# overlap: flops 45 %, AO22 26 %, ICC2 hold cells 27 %; block 0.62).  The R85 bbox-region density cap was not targeted
# (45 % of the core, setup -0.21) and is removed.
# What: every leaf cell driven directly by one of those ports whose fanout reaches a register within 2 cell levels
# (the cell is a register, or it drives a register input) gets a SOFT outer keepout margin, on its right side only, of
# the width of the narrowest cell of the shared hold-cell list (common/lib_cells.tcl qb_hold_cells; width from the
# library, nothing hard-coded).  Soft: only the coarse placer keeps out, optimisation and legalisation (the later hold
# cells) may use the sites, so the reservation holds exactly one hold cell next to each cell that needs one.
proc qb_hold_reserve {} {
    global P
    if {![info exists P(HOLD_RESERVE)]} return
    lassign [qb_lib_cell_min [qb_hold_cells]] wd ht hc
    lassign [qb_hold_reserve_cells $P(HOLD_RESERVE)] cs np nreg ncmb
    create_keepout_margin -type soft -outer [list 0 0 $wd 0] $cs
    foreach_in_collection c $cs { incr rc([get_attribute $c ref_name]) }
    set rl {}; foreach k [lsort [array names rc]] { lappend rl $k:$rc($k) }
    lassign [get_attribute [get_core_area] bbox] c0 c1
    set ca [expr {([lindex $c1 0] - [lindex $c0 0]) * ([lindex $c1 1] - [lindex $c0 1])}]
    set a [expr {[sizeof_collection $cs] * $wd * $ht}]
    qb_line [format "hold_reserve ports %d cells %d (register %d, combinational -> register %d) refs %s keepout soft right %.3f um (%s) area %.1f um2 (%.3f %% of core)" \
        $np [sizeof_collection $cs] $nreg $ncmb $rl $wd $hc $a [expr {100.0 * $a / $ca}]]
}
# narrowest cell of a lib-cell name list (common/lib_cells.tcl qb_hold_cells, qb_data_buffers): {width height name} from the library
proc qb_lib_cell_min {cells} {
    set wl {}
    foreach c $cells { foreach_in_collection l [get_lib_cells */$c] { lappend wl [list [get_attribute $l width] [get_attribute $l height] $c] } }
    return [lindex [lsort -real -index 0 $wl] 0]
}
# Input-port isolation (R88, PI decision; standard hierarchical practice): every input port of P(ISOLATE) (globs; column:
# every non-clock input but act, whose net carries the sized dont_touch act -> act_o feedthrough and its budget) gets one
# buffer at its pin, so every internal net has a cell driver that ICC2 / PrimeTime can size, buffer and noise-fix, and the
# port net is a short stub.  Why [M]: r87 PT noise on the unbuffered 1003 um port net s_rd[487] was
# unfixable, the driver being a port.  How: ICC2's own set_isolate_ports before place_opt (place.tcl), which inserts the
# buffers; driver = the narrowest data buffer of the library minus QC_DONT_USE (common/lib_cells.tcl qb_data_buffers),
# i.e. the least load on the external driver, without -force so optimisation sizes it like any internal cell.  The IO
# budget is untouched: the driving cell / transition and the input delays model the external driver at the port, the
# isolation buffer is internal logic.  Ports whose net has no leaf load are left out (nothing to isolate).
proc qb_isolate_port_set {} {
    global P
    set ports [get_ports $P(ISOLATE) -filter "direction==in"]
    if {![sizeof_collection $ports]} { error "qb_isolate_ports: no input port matches $P(ISOLATE)" }
    set cs [get_attribute -quiet [get_clocks -quiet] sources]
    if {[sizeof_collection $cs]} {
        set ck [remove_from_collection -intersect $ports $cs]
        if {[sizeof_collection $ck]} { error "qb_isolate_ports: P(ISOLATE) matches clock source [get_object_name $ck]" }
    }
    set dt [filter_collection [get_nets -quiet -of_objects $ports] "dont_touch==true"]
    if {[sizeof_collection $dt]} { error "qb_isolate_ports: [sizeof_collection $dt] dont_touch port nets, e.g. [get_object_name [index_collection $dt 0]]" }
    return $ports
}
# port-name families of a port collection with their counts (log lines)
proc qb_port_families {ports} {
    foreach n [get_object_name $ports] { incr f([regsub {\[\d+\]$} $n {}]) }
    return [join [lmap k [lsort [array names f]] { string cat $k : $f($k) }]]
}
proc qb_isolate_ports {} {
    global P
    if {![info exists P(ISOLATE)]} { return 0 }
    set ports {}; set nu 0
    foreach_in_collection p [qb_isolate_port_set] {
        if {[sizeof_collection [get_pins -quiet -leaf -of_objects [get_nets -quiet -of_objects $p] -filter "direction==in"]]} { lappend ports $p } else { incr nu }
    }
    set ports [get_ports $ports]
    lassign [qb_lib_cell_min [qb_data_buffers]] wd ht bc
    set cap [get_attribute -quiet [index_collection [get_lib_pins -quiet -of_objects [index_collection [get_lib_cells */$bc] 0] -filter "direction==in"] 0] capacitance]
    # (-driver excludes -type, a buffer being the default; Q-2019.12 errors on both and goes on: R88 [M])
    set_isolate_ports -driver $bc $ports
    redirect -variable ri { report_isolate_ports $ports }
    if {![regexp {(\d+) of (\d+) ports are isolate_ports} $ri -> a b] || $a != [sizeof_collection $ports]} { error "qb_isolate_ports: report_isolate_ports [string range $ri end-200 end]" }
    set rest [remove_from_collection [get_ports -filter "direction==in"] $ports]
    qb_line [format "isolate ports %d (%s) unloaded %d driver %s (%.3f x %.3f um, I cap %s pF; narrowest of %s) inputs not isolated %d (%s)" \
        [sizeof_collection $ports] [qb_port_families $ports] $nu $bc $wd $ht $cap [join [qb_data_buffers] /] [sizeof_collection $rest] [qb_port_families $rest]]
    return 1
}
# isolation buffers to their pins (place.tcl, between place_opt -to initial_drc, which inserts them, and -from initial_opto):
# ICC2 places them by wire length, not at the pin (R88 [M] r88 first place: port -> buffer Manhattan p50 44.6, max 430.9 um,
# 141 s_rd stubs > 200 um, i.e. still long port-driven nets).  ICC2's magnet_placement pulls each port's one load (the
# buffer, -cells) next to the port terminal and marks it legalize_only, so later placement leaves it there while
# optimisation may still size it.
proc qb_isolate_magnet {} {
    set ports {}; set bufs {}
    foreach_in_collection p [qb_isolate_port_set] {
        set ld [get_pins -quiet -leaf -of_objects [get_nets -quiet -of_objects $p] -filter "direction==in"]
        if {[sizeof_collection $ld] == 1} { lappend ports $p; lappend bufs [get_cells -of_objects $ld] }
    }
    set n [sizeof_collection [magnet_placement -cells [get_cells $bufs] -mark_legalize_only -get_collection [get_ports $ports]]]
    qb_line "place isolate magnet ports [llength $ports] cells pulled $n legalize_only"
}
# isolation gate + metrics (place.tcl, route.tcl, eco.tcl): every loaded P(ISOLATE) port net has exactly one leaf load, a
# one-input buffer cell: a data buffer, a CKBD<n> (optimisation re-sizes through the clock buffers) or a hold cell, which
# hold fixing puts on the stub in front of the isolation buffer (R88 [M] r88 route: 216 ports, e.g. pf[640] -> DEL005);
# error otherwise.  Port-loading cells, their area (all kinds), the stub as Manhattan port-to-load-pin distance and routed wire
proc qb_isolate_report {step} {
    global P
    if {![info exists P(ISOLATE)]} return
    set ok [lsort -unique [concat [qb_data_buffers] [qb_hold_cells]]]
    set ni 0; set nu 0; set bad {}; set area 0.0; set mm {0 -}; set mr {0 -}
    foreach_in_collection p [qb_isolate_port_set] {
        set n [get_nets -quiet -of_objects $p]
        set ld [get_pins -quiet -leaf -of_objects $n -filter "direction==in"]
        if {![sizeof_collection $ld]} { incr nu; continue }
        set c [get_cells -of_objects $ld]; set r [get_attribute $c ref_name]
        if {[sizeof_collection $ld] != 1 || ([lsearch -exact $ok $r] < 0 && ![regexp {^CKBD\d+$} $r])} { lappend bad "[get_object_name $p]:[sizeof_collection $ld]:$r"; continue }
        incr ni; incr rc($r); set area [expr {$area + [get_attribute $c area]}]
        lassign [get_attribute [get_terminals -of_objects $p] bbox] a b
        lassign [get_attribute $ld bbox] e f
        set d [expr {abs(([lindex $a 0]+[lindex $b 0]-[lindex $e 0]-[lindex $f 0])/2.0) + abs(([lindex $a 1]+[lindex $b 1]-[lindex $e 1]-[lindex $f 1])/2.0)}]
        if {$d > [lindex $mm 0]} { set mm [list $d [get_object_name $p]] }
        set w 0.0
        foreach_in_collection s [get_shapes -quiet -of_objects $n -filter "shape_use==detail_route"] {
            lassign [get_attribute $s bbox] e f; set w [expr {$w + max([lindex $f 0]-[lindex $e 0], [lindex $f 1]-[lindex $e 1])}]
        }
        if {$w > [lindex $mr 0]} { set mr [list $w [get_object_name $p]] }
    }
    lassign [get_attribute [get_core_area] bbox] c0 c1
    set ca [expr {([lindex $c1 0] - [lindex $c0 0]) * ([lindex $c1 1] - [lindex $c0 1])}]
    qb_line [format "%s isolate port loads %d refs %s area %.1f um2 (%.3f %% of core) stub max manhattan %.1f um (%s) routed %.1f um (%s) unloaded %d not_isolated %d %s" \
        $step $ni [join [lmap k [lsort [array names rc]] { string cat $k : $rc($k) }]] $area [expr {100.0 * $area / $ca}] \
        {*}$mm {*}$mr $nu [llength $bad] [lrange $bad 0 4]]
    if {[llength $bad]} { error "qb_isolate_report $step: [llength $bad] P(ISOLATE) ports not isolated, e.g. [lrange $bad 0 4]" }
}
# Logical hierarchy flattened at init (R91, PI decision on R89 / R90; init.tcl right after link_block, before any
# constraint or optimisation): ICC2 ungroup_cells -all -flatten.  Why [M]: ICC2 add_buffer_on_route builds a buffer in the
# lowest common hierarchy of the loads it drives and PrimeTime names it in its own (r88: PT's U_PTECO_DRC_BUF15 inside
# u_shd drives U435/I1 and u_shd/U24/A2, ICC2's in u_core drives U435/I1 only), so the netlist ICC2 signs off was not the one
# PT timed.  With one flat level ICC2, PrimeTime (which reads ICC2's netlist) and LVS see the same names and add_buffer_on_route
# has only the top to build in.  ungroup keeps each cell's path as its flat name (u_core/u_pbw/U10, escaped in Verilog),
# so every name and glob of the flow is unchanged (R91 [M] r88 init label: 727 hierarchical -> 0, 220777 leaf cells kept).
# Gate: no hierarchical cell left, leaf-cell count unchanged.
proc qb_flatten {} {
    set nh [sizeof_collection [get_cells -quiet -hierarchical -filter "is_hierarchical==true"]]
    set nl [sizeof_collection [get_cells -quiet -hierarchical -filter "is_hierarchical==false"]]
    ungroup_cells -all -flatten
    set rh [sizeof_collection [get_cells -quiet -hierarchical -filter "is_hierarchical==true"]]
    set rl [sizeof_collection [get_cells -quiet -filter "is_hierarchical==false"]]
    qb_line "init flatten hierarchical cells $nh -> $rh, leaf cells $nl -> $rl (top level)"
    if {$rh || $rl != $nl} { error "qb_flatten: $rh hierarchical cells left, leaf cells $nl -> $rl" }
}
# PT change-list gate (R89; R91 flat), eco.tcl right after sourcing the list, before placement / routing.  It reads the list
# as PT wrote it (common/eco_changes.tcl; nothing is rewritten) and checks, in the block: every named cell (size_cell,
# get_cells, -new_cell_names, add_buffer_on_route buffers), net (-new_net_names), pin (get_pins, get_net -of) and port
# exists; size_cell / insert_buffer / add_buffer_on_route lib cells = the cell's ref; and every new cell of the list against
# PT's new-cell record (qb_eco_cells_file, signoff/pt/drv_eco.tcl): one record per new cell, the ICC2 cell of that name with
# PT's lib cell and exactly PT's load pins (R90 [M]: a name match alone missed a buffer driving 1 of PT's 2 loads).  A line
# of no known form is counted as unparsed.  Writes rpt/eco_names.rpt; returns {summary line, number of failures}.
proc qb_eco_names {chg} {
    current_instance
    set rec [dict create]; set nrec -1; set rf [qb_eco_cells_file $chg]
    if {[file exists $rf]} {
        set fh [open $rf]; set nrec 0
        foreach l [split [read $fh] "\n"] { if {$l ne ""} { incr nrec; dict lappend rec [lindex $l 0] [lrange $l 1 2] } }
        close $fh
    }
    set sc ""; set bad {}; set nu 0
    foreach k {cell net pin port abor ref} { set n($k) 0; set m($k) 0 }
    foreach l [qb_eco_lines $chg] {
        lassign [qb_eco_parse $l $sc] k f
        set want {}
        switch $k {
            scope    { set sc [lindex $f 0]; continue }
            size     { lassign $f c r; lappend want cell $c ref [list $c $r] }
            loc      { lappend want cell [lindex $f 0] }
            ins      { lassign $f ty o r nn c; lappend want $ty $o net $nn cell $c ref [list $c $r] }
            abor     { lassign $f p c r; lappend want pin $p abor $c ref [list $c $r] }
            unparsed { incr nu; lappend bad "unparsed: $l"; continue }
        }
        foreach {k o} $want {
            incr n($k)
            switch $k {
                cell - abor { set ok [sizeof_collection [get_cells -quiet $o]] }
                net  { set ok [sizeof_collection [get_nets -quiet $o]] }
                pin  { set ok [sizeof_collection [get_pins -quiet $o]] }
                port { set ok [sizeof_collection [get_ports -quiet $o]] }
                ref  { lassign $o c r; set ok [expr {[get_attribute -quiet [get_cells -quiet $c] ref_name] eq $r}] }
            }
            if {!$ok} { incr m($k); lappend bad "$k missing/mismatch: $o" }
        }
    }
    # every new cell of the list: exactly one PT record; the ICC2 cell of that name has PT's lib cell and load pins
    set nn 0; set nm 0; set nr 0; set nld 0
    foreach x [qb_eco_new_cells $chg] {
        lassign $x c r; incr nn
        if {$nrec < 0 || ![dict exists $rec $c] || [llength [dict get $rec $c]] != 1} { incr nr; lappend bad "new: no single PT record: $c"; continue }
        lassign [lindex [dict get $rec $c] 0] pr pl
        set ic [get_cells -quiet $c]
        if {![sizeof_collection $ic]} { incr nm; lappend bad "new missing: $c"; continue }
        if {[get_attribute $ic ref_name] ne $pr} { incr nr; lappend bad "new lib cell: $c ICC2 [get_attribute $ic ref_name] PT $pr" }
        set il [qb_eco_loads $ic]
        if {$il ne [lsort -unique $pl]} { incr nld; lappend bad "new loads: $c ICC2 {$il} PT {$pl}" }
    }
    if {$nrec >= 0 && $nrec != $nn} { incr nr; lappend bad "new: PT record $nrec cells, change list $nn new cells" }
    redirect $::R/rpt/eco_names.rpt { puts [join $bad "\n"] }
    set t "eco names [file tail $chg]: cells $n(cell) missing $m(cell)"
    foreach {k w} {net nets pin pins port ports abor abor_buffers ref lib_cells} { append t " $w $n($k) missing $m($k)" }
    append t " new_cells $nn missing $nm load_mismatch $nld record_mismatch $nr unparsed $nu"
    return [list $t [expr {$m(cell) + $m(net) + $m(pin) + $m(port) + $m(abor) + $m(ref) + $nm + $nld + $nr + $nu}]]
}
# leaf cells driven directly by the input ports <globs> that are registers or drive a register input:
# {cells n_ports n_register n_combinational}
proc qb_hold_reserve_cells {globs} {
    set ports [get_ports $globs -filter "direction==in"]
    if {![sizeof_collection $ports]} { error "qb_hold_reserve: no input port matches $globs" }
    set sel {}; set nreg 0; set ncmb 0
    foreach_in_collection c [get_cells -quiet -of_objects [get_pins -quiet -leaf -of_objects [get_nets -of_objects $ports] -filter "direction==in"]] {
        if {[get_attribute $c is_sequential] eq "true"} { incr nreg; lappend sel $c; continue }
        set o [get_nets -quiet -of_objects [get_pins -quiet -of_objects $c -filter "direction==out"]]
        if {![sizeof_collection $o]} continue
        set r [get_cells -quiet -of_objects [get_pins -quiet -leaf -of_objects $o -filter "direction==in"] -filter "is_sequential==true"]
        if {[sizeof_collection $r]} { incr ncmb; lappend sel $c }
    }
    if {![llength $sel]} { error "qb_hold_reserve: no cell selected on $globs" }
    return [list [get_cells $sel] [sizeof_collection $ports] $nreg $ncmb]
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
