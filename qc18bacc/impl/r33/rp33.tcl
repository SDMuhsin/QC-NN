# R33 post-CTS setup-repair replay on a cts db (as impl/pnr/slice_post_cts.tcl + pc24 fix, setup part):
# env R33_DB [cts], QB_IO_LAT, R33_TNS (repair_tns %), R33_TAG; QB_IO_BUDGET from the run config
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set _f [open $::OUT/config.tcl]; set _t [read $_f]; close $_f
eval [string map {r31_snap/ r31_snap4/} $_t]
qc_config
set step [qc_env R33_DB cts]; set tag $::env(R33_TAG)
qc_read_liberty
read_db [qc_env R33_ODBIN $::OUT/db/$step.odb]
set_dont_use $::QC_PNR_DONT_USE
read_sdc $::OUT/db/$step.sdc
qc_set_rc
set_propagated_clock [all_clocks]
estimate_parasitics -placement
set L $::env(QB_IO_LAT); set per [get_property [get_clocks qb_clk] period]
source $::env(QB_IO_BUDGET); qb5_io_apply $per $L
proc st {k} {
    set ws [expr {[sta::worst_slack_cmd max] * 1e9}]
    set ends [find_timing_paths -path_delay max -group_count 200000 -endpoint_count 1 -slack_max 0]
    set n 0; set nio 0; set r2 NA; set rank NA; set r2e ""; set nr2 0
    foreach pe $ends {
        incr n
        set p [[$pe path] pin]; set ep [get_full_name $p]
        set sp [get_full_name [lindex [[$pe path] pins] end]]
        set io [expr {[string first / $ep] < 0 || [string first / $sp] < 0}]
        if {$io} { incr nio } else { incr nr2; if {$r2 eq "NA"} { set r2 [format %.3f [expr {[$pe slack] * 1e9}]]; set rank $n; set r2e "$sp -> $ep" } }
    }
    set a 0.0; foreach i [[ord::get_db_block] getInsts] { set m [$i getMaster]; if {![$m isBlock]} { set a [expr {$a + [$m getWidth] * [$m getHeight]}] } }
    set u [[ord::get_db_tech] getDbUnitsPerMicron]
    puts [format "R33RP %s %s wns %.3f viol %d io %d reg2reg %d | worst reg2reg %s rank %s (%s) | std_um2 %.0f" $::env(R33_TAG) $k $ws $n $nio $nr2 $r2 $rank $r2e [expr {$a / $u / $u}]]
    flush stdout
}
st pre
if {[qc_env R33_IOFP 0]} { set_false_path -from [all_inputs]; set_false_path -to [all_outputs]; st iofp_pre }
set t [clock seconds]
repair_timing -setup -setup_margin 0.0 -repair_tns $::env(R33_TNS) -max_utilization 90
puts "R33RP $tag repair_timing [expr {[clock seconds] - $t}] s"
if {[qc_env R33_IOFP 0]} { st iofp_post; unset_path_exceptions -from [all_inputs]; unset_path_exceptions -to [all_outputs] }
st setup_repair
detailed_placement -max_displacement 500
estimate_parasitics -placement
st setup_legal
if {[qc_env R33_ODB ""] ne ""} { write_db $::env(R33_ODB) }
exit
