# PrimeTime ECO of a routed block.  The design setup is the block's own sign-off script QB_PT_SCRIPT (signoff/pt/
# col_blk.tcl, act_blk.tcl, hub.tcl) up to its design setup (netlist, SDC, SPEF, propagated clock, IO budget: the script
# returns there when ::QB_PT_SETUP_ONLY exists), plus the P&R dont_use list (site/pnr.tcl QC_PNR_DONT_USE).  Two modes:
# * one corner QC_CORNER (pt_shell; act / hub run.sh drveco, OpenROAD, R48): DRV only (fix_eco_drc max_transition /
#   max_capacitance, size_cell + insert_buffer BUFFD2 / 4 / 8); a QB_PT_PRE_ECO file (the changes of an earlier corner)
#   is applied first, so the last corner's <QC_PNR_OUT>/out/drv_eco_<corner>.tcl (icctcl) is the cumulative ECO for
#   OpenROAD (repair/hold_eco.tcl QB35_ECO_TCL).
# * one sign-off round at every corner of QB_ECO_CORNERS together (pt_shell -multi_scenario, DMSA; column run.sh eco,
#   ICC2, R56 results/r56.md): one scenario process per corner, physically aware (occupied_site) on the ICC2 design
#   library QB_ECO_NLIB / block QB_ECO_BLOCK when set;
#     1. fix_eco_drc max_transition, then max_capacitance (as above)
#     2. fix_eco_timing -type hold (size_cell, insert_buffer BUFFD1 / 2); PT keeps setup / DRV of every scenario clean
#   No fixing margins.  Writes <QC_PNR_OUT>/out/eco/pt_eco.tcl (icc2tcl, sourced by flow/icc2/eco.tcl), eco_summary.txt
#   (setup / hold violators, max_tran / max_cap pins per corner before / after DRV / after hold; ECO size), the
#   unfixable-hold reasons hold_unfixable*.
# Env: QC_PNR_OUT, QB_PT_SCRIPT and the variables that script reads (QC_TOP, QC_SDC, QC_PERIOD, ...), QB_ECO_CORES.
proc qb_eco_setup {corner} {
    set ::env(QC_CORNER) $corner
    set ::QB_PT_SETUP_ONLY 1
    uplevel #0 { source $::env(QB_PT_SCRIPT) }
    uplevel #0 { source $::env(QC_FLOW)/site/pnr.tcl }
    foreach p $::QC_PNR_DONT_USE { set c [get_lib_cells -quiet */$p]; if {[sizeof_collection $c]} { set_dont_use $c } }
    uplevel #0 { set eco_report_unfixed_reason_max_endpoints 1000 }
}
proc qb_eco_drc {pmode} {
    foreach ty {max_transition max_capacitance} {
        fix_eco_drc -type $ty -methods {size_cell insert_buffer} -buffer_list {BUFFD2 BUFFD4 BUFFD8} \
            -cell_type {combinational sequential} -physical_mode $pmode -verbose
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
    qb_eco_drc none
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
        puts "QB_ECO_STATE $::qb_eco_corner setup [regexp -all -line {VIOLATED} $s] hold [regexp -all -line {VIOLATED} $h] max_tran [regexp -all -line {VIOLATED} $t] max_cap [regexp -all -line {VIOLATED} $k] cells [sizeof_collection [get_cells -hier -filter is_hierarchical==false]]"
    } }
    foreach l [split $r "\n"] {
        if {[regexp {QB_ECO_STATE (\w+ setup \d+ .*)$} $l -> x]} { puts $sf "$tag $x"; puts "QB_ECO $tag $x" }
    }
    flush $sf
}
qb_eco_state $sf before
puts $sf "physical_mode $pmode"
qb_eco_drc $pmode
qb_eco_state $sf drc
fix_eco_timing -type hold -methods {size_cell insert_buffer} -buffer_list {BUFFD1 BUFFD2} -physical_mode $pmode \
    -verbose -unfixable_reasons_prefix $o/hold_unfixable -unfixable_reasons_format text
qb_eco_state $sf hold
current_scenario [lindex $corners 0]
remote_execute "write_changes -format icc2tcl -output $o/pt_eco.tcl"
current_scenario -all
set t [exec cat $o/pt_eco.tcl]
puts $sf "eco size_cell [regexp -all -line {^\s*size_cell} $t] insert_buffer [regexp -all -line {^\s*(insert_buffer|add_buffer\S*)} $t] lines [llength [split $t "\n"]]"
close $sf
puts [exec cat $o/eco_summary.txt]
stop_hosts
puts "QB_PT_ECO done"
exit
