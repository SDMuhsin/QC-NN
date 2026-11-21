# R45 probe (read-only on a copy dir whose db/ links to a run's checkpoints): ICG enable nets before / after the
# PRE_CTS ICG move (impl/r6c/icg.tcl via impl/r9b/cts_pre.tcl), at placement parasitics.  env R45_STEP (place | cts).
# Run via impl/r29/or29.sh <tag> icgdrv45.tcl <log>.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set step $::env(R45_STEP)
qc_load $step
estimate_parasitics -placement
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set hp {}
foreach i [$blk getInsts] {
    if {![string match CKLNQD* [[$i getMaster] getName]]} continue
    set e [$i findITerm E]; if {$e eq "NULL" || [set n [$e getNet]] eq "NULL"} continue
    set xs {}; set ys {}
    foreach it [$n getITerms] { set b [[$it getInst] getBBox]; lappend xs [$b xMin]; lappend ys [$b yMin] }
    lappend hp [expr {(([tcl::mathfunc::max {*}$xs] - [tcl::mathfunc::min {*}$xs]) + ([tcl::mathfunc::max {*}$ys] - [tcl::mathfunc::min {*}$ys])) / $u}]
}
set hp [lsort -real $hp]; set k [llength $hp]
puts [format "R45_ICGE %s nets %d HPWL p50 %.0f p90 %.0f max %.0f um" $step $k [lindex $hp [expr {$k / 2}]] [lindex $hp [expr {int($k * 0.9)}]] [lindex $hp end]]
set rf $::OUT/r45_slew_$step.rpt
qc_to $rf { report_check_types -max_slew -max_capacitance -violators }
set f [open $rf]; set t [read $f]; close $f
puts "R45_DRV $step all_violator_lines [regexp -all -line {VIOLATED} $t] icg_E [regexp -all -line {/E\s.*VIOLATED} $t] slew_count [sta::max_slew_violation_count] cap_count [sta::max_capacitance_violation_count]"
exit
