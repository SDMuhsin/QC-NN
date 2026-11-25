# PrimeTime ECO of a routed block.  The design setup is the block's own sign-off script QB_PT_SCRIPT (signoff/pt/
# col_blk.tcl, act_blk.tcl, hub.tcl) up to its design setup (netlist, SDC, SPEF, propagated clock, IO budget: the script
# returns there when ::QB_PT_SETUP_ONLY exists), plus the shared dont_use list (site.tcl QC_DONT_USE, read by DC too).  Two modes:
# * one corner QC_CORNER (pt_shell; act / hub run.sh drveco, OpenROAD, R48): DRV only (fix_eco_drc max_transition /
#   max_capacitance / noise, size_cell + insert_buffer of qb_eco_buffers); a QB_PT_PRE_ECO file (the changes of an earlier corner)
#   is applied first, so the last corner's <QC_PNR_OUT>/out/drv_eco_<corner>.tcl (icctcl) is the cumulative ECO for
#   OpenROAD (repair/hold_eco.tcl QB35_ECO_TCL).
# * one sign-off round at every corner of QB_ECO_CORNERS together (pt_shell -multi_scenario, DMSA; column run.sh eco,
#   ICC2, R56 results/r56.md): one scenario process per corner, physically aware (occupied_site) on the ICC2 design
#   library QB_ECO_NLIB / block QB_ECO_BLOCK (required in both modes, R81);
#     1. fix_eco_drc max_transition, then max_capacitance, then crosstalk noise (R67; update_noise in the setup), each
#        physically aware only (R81, qb_eco_drc); max_transition / max_capacitance also in the clock network (R75,
#        qb_eco_clock_buffers), physically aware with the clock-network physical data (R81)
#     2. fix_eco_timing -type setup (size_cell, insert_buffer of qb_eco_buffers: every BUFFD* not dont_use; R67, R69)
#     3. fix_eco_timing -type hold (size_cell, insert_buffer of common/lib_cells.tcl qb_hold_cells: the list ICC2 hold
#        fixing uses, R84); PT keeps setup / DRV of every scenario clean
#   No fixing margins.  Writes <QC_PNR_OUT>/out/eco/pt_eco.tcl (icc2tcl, sourced by flow/icc2/eco.tcl), eco_summary.txt
#   (setup / hold violators, max_tran / max_cap pins (of them in the clock network) per corner before / after DRV /
#   after hold; ECO size), the unfixable reasons of every pass (<type>_unfixable*, drc_<type>[_clock]_unfixable*).
# No physical_mode none anywhere (R81, PI decision): R80 [M] the r79 clock-network pass without physical constraints
# upsized a FIXED CTS inverter in place (cts_inv_36669764 CKND8 -> CKND12), which then overlapped g_r_12 U23 (the LVS
# short).  ICC2 eco.tcl cannot legalise around an in-place-sized fixed cell, so a change PT cannot make physically is
# left unfixed and REPORTED (unfixable reasons + qb_eco_state), never forced.
# Env: QC_PNR_OUT, QB_PT_SCRIPT and the variables that script reads (QC_TOP, QC_SDC, QC_PERIOD, ...), QB_ECO_CORES.
proc qb_eco_setup {corner} {
    set ::env(QC_CORNER) $corner
    set ::QB_PT_SETUP_ONLY 1
    uplevel #0 { source $::env(QB_PT_SCRIPT) }
    # site/pnr.tcl: decap / filler cells of set_eco_options; the dont_use list is site.tcl's (sourced by the PT script)
    uplevel #0 { source $::env(QC_FLOW)/site/pnr.tcl; source $::env(QC_FLOW)/../../qc18bacc/flow/common/lib_cells.tcl }
    # clock-tree lib cells (common/lib_cells.tcl qb_clock_cells): the only sizing candidates of the clock-network pass (qb_eco_drc)
    define_user_attribute -type boolean -class lib_cell qb_clock_cell
    set_user_attribute -quiet [get_lib_cells [lmap g [qb_clock_cells] { string cat */ $g }]] qb_clock_cell true
    foreach p $::QC_DONT_USE { set c [get_lib_cells -quiet */$p]; if {[sizeof_collection $c]} { set_dont_use $c } }
    qb_dont_use_gate eco_$corner 1
    uplevel #0 { set eco_report_unfixed_reason_max_endpoints 1000 }
    # crosstalk noise of the sign-off (signoff/pt/common.tcl qb_pt_si_checks), fixed by fix_eco_drc -type noise
    update_noise
}
# ECO buffers: every BUFFD* lib cell the dont_use list allows (R69: the former hand list BUFFD2 / 4 / 8 left a 1.5 mm
# BUFFD16 HFS net at ml max_transition unfixable, reason D; with BUFFD12 / 16 allowed one BUFFD16 fixes it [M])
proc qb_eco_buffers {} {
    return [lsort -unique [lmap c [get_object_name [get_lib_cells -filter dont_use==false */BUFFD*]] { file tail $c }]]
}
# clock-network ECO buffers: the CTS buffers of site/pnr.tcl QC_PNR_CTS_BUF (cts.tcl) the dont_use list allows.  R75 [M]:
# ICC2 leaves a clock-gate output over its limit (CTS sizes the gate at zero slack on its estimate, detail clock routing
# adds the rest: r74 / r75 clk_gate_shd_reg_3 CKLNQD2 0.119 / 0.1185 pF at ss) and its post-route clock DRC fixing never
# resizes a clock gate (flow/icc2/cts.tcl); fix_eco_drc -cell_type clock_network fixes it (r74 ss: one CKBD4 after the gate).
proc qb_eco_clock_buffers {} {
    set b {}; foreach g $::QC_PNR_CTS_BUF { lappend b {*}[lmap c [get_object_name [get_lib_cells -quiet -filter dont_use==false */$g]] { file tail $c }] }
    return [lsort -unique $b]
}
# DRV / noise fixing, physically aware only (occupied_site; R81, PI decision, header): what PT cannot fix in place or on
# free sites stays a reported violator (unfixable reasons <pfx>drc_<type>[_clock]*, qb_eco_state counts), not a change
# without a location.  (R69 [M] had one port-driven noise victim, column s_rd[523], unfixable in occupied_site and fixed
# only without physical constraints: such a case is now reported for the PI.)
# Clock-network DRV (cbufs given, DMSA master): physically aware too, with set_eco_options -physical_enable_clock_data
# in every scenario (qb_eco_phys; PT man fix_eco_drc "Clock Network Fixing": physically aware clock fixing needs it),
# so PT sees the clock cells' placement and never sizes a fixed clock cell into its neighbour; sizing restricted to
# the clock-tree lib cells (PT otherwise uses every alternative: r75 eco 1 [M] sized cts_inv_34929379 to INVD8;
# fix_eco_drc man: eco_alternative_cell_attribute_restrictions), set in the scenarios for this pass only.
proc qb_eco_drc {pfx bufs {cbufs {}}} {
    foreach ty {max_transition max_capacitance noise} {
        fix_eco_drc -type $ty -methods {size_cell insert_buffer} -buffer_list $bufs \
            -cell_type {combinational sequential} -physical_mode occupied_site -verbose \
            -unfixable_reasons_prefix ${pfx}drc_$ty -unfixable_reasons_format text
        if {[llength $cbufs] && $ty ne "noise"} {
            remote_execute { set eco_alternative_cell_attribute_restrictions qb_clock_cell }
            fix_eco_drc -type $ty -methods {size_cell insert_buffer} -buffer_list $cbufs -cell_type clock_network \
                -physical_mode occupied_site -verbose -unfixable_reasons_prefix ${pfx}drc_${ty}_clock -unfixable_reasons_format text
            remote_execute { set eco_alternative_cell_attribute_restrictions "" }
        }
    }
}
# physical data of the ECO (both modes, R81): the ICC2 design library QB_ECO_NLIB / block QB_ECO_BLOCK, required (no
# logic-only fallback), clock-network physical data on (-physical_enable_clock_data, PT Q-2019.12-SP2 set_eco_options
# man: "Without this option, ECO operations ignore physical data for the clock network").
# The kit's DCAP* / FILL* are not PT standard fillers: without -filler_cell_names every row site is occupied
# (R56: 0 fillers identified, fix_eco_timing -type hold then made 0 changes)
proc qb_eco_phys {corner} {
    foreach v {QB_ECO_NLIB QB_ECO_BLOCK} { if {![info exists ::env($v)]} { error "qb_eco_phys: $v not set (the ECO is physically aware only, R81)" } }
    set_eco_options -physical_icc2_lib $::env(QB_ECO_NLIB) -physical_icc2_blocks $::env(QB_ECO_BLOCK) -physical_enable_clock_data \
        -filler_cell_names [concat $::QC_PNR_DCAP $::QC_PNR_FILL] -log_file $::env(QC_PNR_OUT)/out/eco/phys_$corner.log
}
# violator pins of a report_constraint -max_transition / -max_capacitance report that are in the clock network (PT pin
# attribute is_clock_network): the post-route clock DRV of R81 decision 3, counted before any ECO (qb_eco_state)
proc qb_eco_clk_viol {rpt} {
    set n 0
    foreach {- p} [regexp -all -inline -line {^\s*(\S+)\s+[-0-9.]+\s+[-0-9.]+\s+[-0-9.]+\s+\(VIOLATED} $rpt] {
        set q [get_pins -quiet $p]
        if {[sizeof_collection $q] && [get_attribute -quiet $q is_clock_network] eq "true"} { incr n }
    }
    return $n
}
if {[info exists ::qb_eco_corner]} {
    # DMSA scenario process: design setup of this corner, then back to the master
    qb_eco_setup $::qb_eco_corner
    qb_eco_phys $::qb_eco_corner
    return
}
if {![info exists ::env(QB_ECO_CORNERS)]} {
    set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT)
    qb_eco_setup $corner
    file mkdir $dir/out/eco
    qb_eco_phys $corner
    if {[info exists ::env(QB_PT_PRE_ECO)] && [file exists $::env(QB_PT_PRE_ECO)]} { source $::env(QB_PT_PRE_ECO); puts "QB_DRV_ECO applied $::env(QB_PT_PRE_ECO)" }
    update_timing
    qb_pt_drv stdout
    qb_eco_drc $dir/out/eco/${corner}_ [qb_eco_buffers]
    qb_pt_drv stdout
    write_changes -format icctcl -output $dir/out/drv_eco_$corner.tcl
    puts "QB_DRV_ECO done $corner"
    exit
}
set eco_report_unfixed_reason_max_endpoints 1000
set dir $::env(QC_PNR_OUT); set o $dir/out/eco; file mkdir $o
set corners $::env(QB_ECO_CORNERS)
set pmode occupied_site
set_host_options -num_processes [llength $corners] -max_cores [expr {[info exists ::env(QB_ECO_CORES)] ? $::env(QB_ECO_CORES) : 4}]
set multi_scenario_working_directory $o/work
set multi_scenario_merged_error_log $o/merged_errors.log
foreach c $corners {
    set qb_eco_corner $c
    create_scenario -name $c -specific_variables {qb_eco_corner} -specific_data [file normalize [info script]]
}
unset qb_eco_corner
start_hosts
current_session $corners
set sf [open $o/eco_summary.txt w]
proc qb_eco_state {sf tag} {
    redirect -variable r { remote_execute -verbose {
        redirect -variable s { report_constraint -max_delay -all_violators -nosplit }
        redirect -variable h { report_constraint -min_delay -all_violators -nosplit }
        redirect -variable t { report_constraint -max_transition -all_violators -nosplit }
        redirect -variable k { report_constraint -max_capacitance -all_violators -nosplit }
        redirect -variable n { report_noise -all_violators -nosplit }
        puts "QB_ECO_STATE $::qb_eco_corner setup [regexp -all -line {VIOLATED} $s] hold [regexp -all -line {VIOLATED} $h] max_tran [regexp -all -line {VIOLATED} $t] max_cap [regexp -all -line {VIOLATED} $k] clock_max_tran [qb_eco_clk_viol $t] clock_max_cap [qb_eco_clk_viol $k] noise [regexp -all -line {^\s*\S+ \(\S+\)\s+[-0-9.]+\s+[-0-9.]+\s+[-0-9.]+\s*$} $n] cells [sizeof_collection [get_cells -hier -filter is_hierarchical==false]]"
    } }
    foreach l [split $r "\n"] {
        if {[regexp {QB_ECO_STATE (\w+ setup \d+ .*)$} $l -> x]} { puts $sf "$tag $x"; puts "QB_ECO $tag $x" }
    }
    flush $sf
}
qb_eco_state $sf before
# buffer list of the scenario processes (the master has no libraries; every scenario has the same dont_use list)
current_scenario [lindex $corners 0]
redirect -variable r { remote_execute -verbose { puts "QB_ECO_BUFS [qb_eco_buffers]"; puts "QB_ECO_CBUFS [qb_eco_clock_buffers]" } }
current_scenario -all
if {![regexp {QB_ECO_BUFS (BUFF[^\n]*)} $r -> bufs]} { error "QB_PT_ECO: no ECO buffer list from [lindex $corners 0]" }
if {![regexp {QB_ECO_CBUFS (CK[^\n]*)} $r -> cbufs]} { error "QB_PT_ECO: no clock ECO buffer list from [lindex $corners 0]" }
puts $sf "physical_mode $pmode (every pass, clock network with physical clock data); buffers $bufs; clock network buffers $cbufs"
qb_eco_drc $o/ $bufs $cbufs
qb_eco_state $sf drc
# setup (R67): residual setup violators of the sign-off timing (the column's act feedthroughs are dont_touch, R68)
fix_eco_timing -type setup -methods {size_cell insert_buffer} -buffer_list $bufs -physical_mode $pmode \
    -verbose -unfixable_reasons_prefix $o/setup_unfixable -unfixable_reasons_format text
qb_eco_state $sf setup
# hold (R84): the ONE hold-cell list of ICC2 and this ECO (common/lib_cells.tcl qb_hold_cells: BUFFD<n> + the delay cells
# DEL<n>); the hold-only cells (site.tcl QC_HOLD_ONLY) are dont_use in every scenario until here, so DRV / setup never use them
current_scenario [lindex $corners 0]
redirect -variable r { remote_execute -verbose { puts "QB_ECO_HBUFS [qb_hold_cells]" } }
current_scenario -all
if {![regexp {QB_ECO_HBUFS (BUFF[^\n]*)} $r -> hbufs]} { error "QB_PT_ECO: no hold cell list from [lindex $corners 0]" }
remote_execute { foreach p [qb_hold_only] { set c [get_lib_cells -quiet */$p]; if {[sizeof_collection $c]} { set_dont_use $c false } } }
puts $sf "hold cells $hbufs"
fix_eco_timing -type hold -methods {size_cell insert_buffer} -buffer_list $hbufs -physical_mode $pmode \
    -verbose -unfixable_reasons_prefix $o/hold_unfixable -unfixable_reasons_format text
qb_eco_state $sf hold
current_scenario [lindex $corners 0]
remote_execute "write_changes -format icc2tcl -output $o/pt_eco.tcl"
current_scenario -all
# write_changes writes no file when the round made no change (R64 [M]: round 2 at its fixed point); the change list is
# then empty, so flow/icc2/eco.tcl applies nothing
if {![file exists $o/pt_eco.tcl]} { set f [open $o/pt_eco.tcl w]; puts $f "# no ECO changes"; close $f }
set t [exec cat $o/pt_eco.tcl]
puts $sf "eco size_cell [regexp -all -line {^\s*size_cell} $t] insert_buffer [regexp -all -line {^\s*(insert_buffer|add_buffer\S*)} $t] lines [llength [split $t "\n"]]"
close $sf
puts [exec cat $o/eco_summary.txt]
stop_hosts
puts "QB_PT_ECO done"
exit
