# Sign-off limits (R99): the committed values of common/limits.txt, the one source of truth (DC, PrimeTime, ICC2).
#   qb_limit <name>   the value in force: the environment variable <name> if set and not empty (an experiment), else
#                     the committed value; error for a name limits.txt does not have
#   qb_limits         "<name> <value> ..." of every limit of limits.txt as in force (PrimeTime logs it as QB_PT_LIMITS,
#                     signoff/pt/blk.tcl; signoff/verdict.py gate limits compares it with limits.txt)
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
