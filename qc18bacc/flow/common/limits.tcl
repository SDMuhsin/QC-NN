# Sign-off limits (R99): the committed values of common/limits.txt, the one source of truth (DC, PrimeTime, ICC2).
#   qb_limit <name>   the value in force: the environment variable <name> if set and not empty (an experiment), else
#                     the committed value; error for a name limits.txt does not have
#   qb_limits         "<name> <value> ..." of every limit of limits.txt as in force (PrimeTime logs it as QB_PT_LIMITS,
#                     signoff/pt/blk.tcl; signoff/verdict.py gate limits compares it with limits.txt; DC records it in
#                     run.env, ::QC_RECORD below)
#   qb_io_delay <P>   IO delay at period P of the ports outside a block IO budget: QC_IO_PCT % of P (constraints.sdc,
#                     common/block_sdc.tcl; R103: block_sdc had its own 0.2 P)
#   qb_max_tran <P>   design max transition at period P: min(QC_MAX_TRAN, QC_MAX_TRAN_PCT % of P) (constraints.sdc,
#                     common/block_sdc.tcl; R103: both had their own min(0.5, 0.1 P))
set ::QB_LIMITS_FILE [file join [file dirname [file normalize [info script]]] limits.txt]
proc qb_limits_committed {} {
    set f [open $::QB_LIMITS_FILE]; set t [read $f]; close $f
    set v {}
    foreach l [split $t "\n"] {
        regsub {#.*} $l {} l
        if {[llength $l] == 0} continue
        if {[llength $l] != 2} { error "qb_limits: line '$l' of $::QB_LIMITS_FILE is not '<name> <value>'" }
        lappend v {*}$l
    }
    return $v
}
proc qb_limit {name} {
    set c [dict create {*}[qb_limits_committed]]
    if {![dict exists $c $name]} { error "qb_limit: no limit $name in $::QB_LIMITS_FILE" }
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return [dict get $c $name]
}
proc qb_limits {} { join [lmap {n -} [qb_limits_committed] { list $n [qb_limit $n] }] }
# DC records the limits in force in run.env after its hook (flow/tsmc65/common/knobs.tcl qc_knobs_record, R107)
set ::QC_RECORD(limits) qb_limits
proc qb_io_delay {per} { expr {$per * [qb_limit QC_IO_PCT] / 100.0} }
proc qb_max_tran {per} { expr {min([qb_limit QC_MAX_TRAN], $per * [qb_limit QC_MAX_TRAN_PCT] / 100.0)} }
