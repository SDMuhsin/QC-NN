# PrimeTime ECO of a routed block.  The design setup is the block's own sign-off script QB_PT_SCRIPT (signoff/pt/
# col_blk.tcl, act_blk.tcl, hub.tcl) up to its design setup (netlist, SDC, SPEF, propagated clock, IO budget: the script
# returns there when ::QB_PT_SETUP_ONLY exists), plus the shared dont_use list (site.tcl QC_DONT_USE, read by DC too).  Two modes:
# * one corner QC_CORNER (pt_shell; act / hub run.sh drveco, OpenROAD, R48): DRV only (fix_eco_drc max_transition /
#   max_capacitance / noise, size_cell + insert_buffer of qb_eco_buffers); a QB_PT_PRE_ECO file (the changes of an earlier corner)
#   is applied first, so the last corner's <QC_PNR_OUT>/out/drv_eco_<corner>.tcl (icctcl) is the cumulative ECO for
#   OpenROAD (repair/hold_eco.tcl QB35_ECO_TCL).
# * one sign-off round at every corner of QB_ECO_CORNERS together (pt_shell -multi_scenario, DMSA; column run.sh eco,
#   ICC2, R56 results/r56.md): one scenario process per corner, physically aware (occupied_site) on the ICC2 design
#   library QB_ECO_NLIB / block QB_ECO_BLOCK when set;
#     1. fix_eco_drc max_transition, then max_capacitance, then crosstalk noise (R67; update_noise in the setup), each
#        physically aware, then without physical constraints for what remains (R69, qb_eco_drc)
#     2. fix_eco_timing -type setup (size_cell, insert_buffer of qb_eco_buffers: every BUFFD* not dont_use; R67, R69)
#     3. fix_eco_timing -type hold (size_cell, insert_buffer BUFFD1 / 2); PT keeps setup / DRV of every scenario clean
#   No fixing margins.  Writes <QC_PNR_OUT>/out/eco/pt_eco.tcl (icc2tcl, sourced by flow/icc2/eco.tcl), eco_summary.txt
#   (setup / hold violators, max_tran / max_cap pins per corner before / after DRV / after hold; ECO size), the
#   unfixable-hold reasons hold_unfixable*.
# Env: QC_PNR_OUT, QB_PT_SCRIPT and the variables that script reads (QC_TOP, QC_SDC, QC_PERIOD, ...), QB_ECO_CORES.
proc qb_eco_setup {corner} {
    set ::env(QC_CORNER) $corner
    set ::QB_PT_SETUP_ONLY 1
    uplevel #0 { source $::env(QB_PT_SCRIPT) }
    # site/pnr.tcl: decap / filler cells of set_eco_options; the dont_use list is site.tcl's (sourced by the PT script)
    uplevel #0 { source $::env(QC_FLOW)/site/pnr.tcl }
    foreach p $::QC_DONT_USE { set c [get_lib_cells -quiet */$p]; if {[sizeof_collection $c]} { set_dont_use $c } }
    uplevel #0 { set eco_report_unfixed_reason_max_endpoints 1000 }
    # crosstalk noise of the sign-off (signoff/pt/common.tcl qb_pt_si_checks), fixed by fix_eco_drc -type noise
    update_noise
}
# ECO buffers: every BUFFD* lib cell the dont_use list allows (R69: the former hand list BUFFD2 / 4 / 8 left a 1.5 mm
# BUFFD16 HFS net at ml max_transition unfixable, reason D; with BUFFD12 / 16 allowed one BUFFD16 fixes it [M])
proc qb_eco_buffers {} {
    return [lsort -unique [lmap c [get_object_name [get_lib_cells -filter dont_use==false */BUFFD*]] { file tail $c }]]
}
# DRV / noise fixing: physically aware first (pmode), then, for what that leaves, without physical constraints: the new
# cells have no PT location and ICC2 places + legalises them (flow/icc2/eco.tcl place_eco_cells).  R69 [M]: a port-
# driven victim net (column s_rd[523], 800 um, 0.13 pF coupling) is unfixable in occupied_site (reasons I P, any buffer
# list) and fixed by one BUFFD8 without physical constraints.
proc qb_eco_drc {pmode bufs} {
    foreach ty {max_transition max_capacitance noise} {
        foreach pm [expr {$pmode eq "none" ? "none" : [list $pmode none]}] {
            fix_eco_drc -type $ty -methods {size_cell insert_buffer} -buffer_list $bufs \
                -cell_type {combinational sequential} -physical_mode $pm -verbose
        }
    }
}
if {[info exists ::qb_eco_corner]} {
    # DMSA scenario process: design setup of this corner, then back to the master
    qb_eco_setup $::qb_eco_corner
    if {[info exists ::env(QB_ECO_NLIB)]} {
        # the kit's DCAP* / FILL* are not PT standard fillers: without -filler_cell_names every row site is occupied
        # (R56: 0 fillers identified, fix_eco_timing -type hold then made 0 changes)
        set_eco_options -physical_icc2_lib $::env(QB_ECO_NLIB) -physical_icc2_blocks $::env(QB_ECO_BLOCK) \
            -filler_cell_names [concat $::QC_PNR_DCAP $::QC_PNR_FILL] -log_file $::env(QC_PNR_OUT)/out/eco/phys_$::qb_eco_corner.log
    }
    return
}
if {![info exists ::env(QB_ECO_CORNERS)]} {
    set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT)
    qb_eco_setup $corner
    if {[info exists ::env(QB_PT_PRE_ECO)] && [file exists $::env(QB_PT_PRE_ECO)]} { source $::env(QB_PT_PRE_ECO); puts "QB_DRV_ECO applied $::env(QB_PT_PRE_ECO)" }
    update_timing
    qb_pt_drv stdout
    qb_eco_drc none [qb_eco_buffers]
    qb_pt_drv stdout
    write_changes -format icctcl -output $dir/out/drv_eco_$corner.tcl
    puts "QB_DRV_ECO done $corner"
    exit
}
set eco_report_unfixed_reason_max_endpoints 1000
set dir $::env(QC_PNR_OUT); set o $dir/out/eco; file mkdir $o
set corners $::env(QB_ECO_CORNERS)
set pmode [expr {[info exists ::env(QB_ECO_NLIB)] ? "occupied_site" : "none"}]
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
        puts "QB_ECO_STATE $::qb_eco_corner setup [regexp -all -line {VIOLATED} $s] hold [regexp -all -line {VIOLATED} $h] max_tran [regexp -all -line {VIOLATED} $t] max_cap [regexp -all -line {VIOLATED} $k] noise [regexp -all -line {^\s*\S+ \(\S+\)\s+[-0-9.]+\s+[-0-9.]+\s+[-0-9.]+\s*$} $n] cells [sizeof_collection [get_cells -hier -filter is_hierarchical==false]]"
    } }
    foreach l [split $r "\n"] {
        if {[regexp {QB_ECO_STATE (\w+ setup \d+ .*)$} $l -> x]} { puts $sf "$tag $x"; puts "QB_ECO $tag $x" }
    }
    flush $sf
}
qb_eco_state $sf before
# buffer list of the scenario processes (the master has no libraries; every scenario has the same dont_use list)
current_scenario [lindex $corners 0]
redirect -variable r { remote_execute -verbose { puts "QB_ECO_BUFS [qb_eco_buffers]" } }
current_scenario -all
if {![regexp {QB_ECO_BUFS (BUFF[^\n]*)} $r -> bufs]} { error "QB_PT_ECO: no ECO buffer list from [lindex $corners 0]" }
puts $sf "physical_mode $pmode then none; buffers $bufs"
qb_eco_drc $pmode $bufs
qb_eco_state $sf drc
# setup (R67): residual setup violators of the sign-off timing (the column's act feedthroughs are dont_touch, R68)
fix_eco_timing -type setup -methods {size_cell insert_buffer} -buffer_list $bufs -physical_mode $pmode \
    -verbose -unfixable_reasons_prefix $o/setup_unfixable -unfixable_reasons_format text
qb_eco_state $sf setup
fix_eco_timing -type hold -methods {size_cell insert_buffer} -buffer_list {BUFFD1 BUFFD2} -physical_mode $pmode \
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
