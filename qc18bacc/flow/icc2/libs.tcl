# G1 (icc2_lm_shell): standard-cell NDM reference library from the kit liberty (.db, every corner of site.tcl QC_LIB)
# + the 9-metal cell LEF (site/pnr.tcl QC_PNR_LEF) on the ICC2 tech file (site.tcl QC_TF, tsmcn65_9lmT2 = 6X2Z).
# lib.workspace.keep_all_physical_cells keeps the LEF-only physical cells (FILL*: no liberty model).
# The kit LEF has the antenna diode (site/pnr.tcl QC_PNR_DIODE, ANTENNA, pin I) as CLASS CORE, not CORE ANTENNACELL, so
# the NDM made it an ordinary lib_cell with a non-diode pin and Zroute found no diode (R59 route.log ZRT-302 / ZRT-301:
# insertion off): the cell gets design_type diode and its pin is_diode, as an ANTENNACELL would (R62 [M], routed test
# design: ZRT-302 stays with design_type alone, goes with is_diode; route.detail.diode_libcell_names takes the bare name).
# Writes ::QB_NDM once (kept when it exists: delete it to rebuild); check_workspace report in <run>/rpt/libs_check.rpt.
source [file dirname [info script]]/common.tcl
if {![file exists $::QB_NDM]} {
    file mkdir [file dirname $::QB_NDM]
    set ws [file rootname [file tail $::QB_NDM]]
    set_app_options -name lib.workspace.keep_all_physical_cells -value true
    create_workspace $ws -flow normal -technology $::QC_TF
    set dbs {}; foreach c $::QC_CORNERS { lappend dbs [qc_db $c] }
    read_db $dbs
    read_lef $::QC_PNR_LEF
    set dio [get_lib_cells */[lindex $::QC_PNR_DIODE 0]]
    set dpin [get_lib_pins */[lindex $::QC_PNR_DIODE 0]/[lindex $::QC_PNR_DIODE 1]]
    set_attribute -objects $dio -name design_type -value diode
    set_attribute -objects $dpin -name is_diode -value true
    qb_line "libs diode [get_object_name $dio] design_type [lsort -unique [get_attribute $dio design_type]] pin is_diode [lsort -unique [get_attribute $dpin is_diode]]"
    redirect -tee $::R/rpt/libs_check.rpt { check_workspace }
    commit_workspace -output $::QB_NDM
}
qb_line "libs ndm $::QB_NDM tf [file tail $::QC_TF] lef [file tail $::QC_PNR_LEF] corners $::QC_CORNERS"
puts "QB_ICC2_DONE libs"
