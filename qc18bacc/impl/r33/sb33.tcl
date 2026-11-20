# R33: series-buffer census + A/B on a placed db.  Env: QC_PNR_OUT (run dir), R33_DB (step), R33_MODE (census|rebuf)
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set _f [open $::OUT/config.tcl]; set _t [read $_f]; close $_f
eval [string map {r31_snap/ r31_snap4/} $_t]
qc_config
set step $::env(R33_DB)
qc_read_liberty
read_db [qc_env R33_ODBIN $::OUT/db/$step.odb]
set_dont_use $::QC_PNR_DONT_USE
read_sdc $::OUT/db/$step.sdc
qc_set_rc
if {$step ne "place"} { set_propagated_clock [all_clocks] }
proc isbuf {m} { return [regexp {^(BUFF|CKBD)} [$m getName]] }
proc census {tag} {
    set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
    set nb 0; set ab 0.0; set np 0; set ap 0.0; array set pfx {}; set dl {}
    foreach i [$blk getInsts] {
        set m [$i getMaster]; if {![isbuf $m]} continue
        incr nb; set a [expr {[$m getWidth] * [$m getHeight] / $u / $u}]; set ab [expr {$ab + $a}]
        set o [$i findITerm Z]; if {$o eq "NULL"} continue
        set n [$o getNet]; if {$n eq "NULL" || [$n getSigType] ne "SIGNAL" || [llength [$n getBTerms]]} continue
        set sinks {}; foreach it [$n getITerms] { if {[$it isInputSignal]} { lappend sinks $it } }
        if {[llength $sinks] != 1} continue
        set s [[lindex $sinks 0] getInst]
        if {![isbuf [$s getMaster]]} continue
        lassign [$i getLocation] x1 y1; lassign [$s getLocation] x2 y2
        set d [expr {(abs($x1 - $x2) + abs($y1 - $y2)) / $u}]
        if {$d < 10.0} {
            incr np; set ap [expr {$ap + $a}]
            regexp {^([a-z_]+)} [$i getName] -> p; if {![info exists p]} { set p other }
            incr pfx($p)
        }
        lappend dl $d
    }
    set dl [lsort -real $dl]; set k [llength $dl]
    puts [format "R33C %s buffers %d area %.0f um2 | buf->single-buf nets %d, p10 %.1f p50 %.1f um | adjacent (<10 um) pairs %d (area %.0f um2) by prefix %s" \
        $tag $nb $ab $k [lindex $dl [expr {$k / 10}]] [lindex $dl [expr {$k / 2}]] $np $ap [array get pfx]]
    flush stdout
}
proc wns {tag} {
    set ws [sta::worst_slack_cmd max]
    set n NA; catch { set n [sta::endpoint_violation_count max] }
    set r2 NA; set r2p ""
    if {[catch { set pe [lindex [find_timing_paths -from [all_registers -clock_pins] -to [all_registers -data_pins] -path_delay max -group_count 1] 0]
            set r2 [format %.3f [expr {[$pe slack] * 1e9}]]; set r2p "[get_full_name [[$pe path] pin]]" } e]} { puts "R33E $e" }
    puts [format "R33W %s wns %.3f viol_endpoints %s reg2reg %s (%s) %s" $tag [expr {$ws * 1e9}] $n $r2 $r2p [qc_util]]; flush stdout
}
proc pathbufs {tag} {
    # worst path: number of buffer stages and their summed delay; adjacent-buffer stages
    set pe [lindex [find_timing_paths -path_delay max -group_count 1] 0]
    set nb 0; set db 0.0; set prev ""; set pa 0.0
    foreach pt [$pe path] {
        # sta PathRef iteration is version dependent: use report fallback
    }
}
estimate_parasitics -placement
wns ${step}_loaded
census $step
if {[qc_env R33_MODE census] eq "rebuf"} {
    set_max_transition [qc_env QB_MAXTRAN 0.4] [current_design]
    set_max_fanout [qc_env QB21_MAXFO 32] [current_design]
    set n0 [llength [[ord::get_db_block] getInsts]]
    remove_buffers
    puts "R33 remove_buffers [expr {$n0 - [llength [[ord::get_db_block] getInsts]]}] removed"
    estimate_parasitics -placement
    wns ${step}_nobuf
    qc_repair_drv
    estimate_parasitics -placement
    wns ${step}_rebuf_unlegal
    detailed_placement -max_displacement 500
    estimate_parasitics -placement
    wns ${step}_rebuf_legal
    census ${step}_rebuf
    report_checks -path_delay max -fields {input_pins slew cap fanout} -digits 3 > $::env(R33_RPT)
    write_db $::env(R33_ODB)
}
exit
