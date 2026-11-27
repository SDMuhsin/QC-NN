# Design knobs of the DC hooks and their record (sourced by common/lib.tcl).  A QC_HOOK, and each file it sources,
# declares the environment knobs it reads ONCE, with their defaults:  qc_knobs_declare {<name> <default> ...}  (a name declared
# twice with two defaults is an error), and reads them through  qc_knob <name>  (the environment value if set and not
# empty, else the declared default; an undeclared name is an error, so no read escapes the declaration).
# syn/dc.tcl appends the record to the run's run.env after the hook (qc_knobs_record): one comment line per declared
# knob, "# knob <name> <value in force> env|default", and one per ::QC_RECORD(<key>) command a sourced design file
# registered, "# <key> <its result>" (qc18bacc common/limits.tcl: the sign-off limits in force).  Comment lines: the
# shell scripts that source run.env (sta/run_pt.sh, pnr/run_pt_post.sh) take nothing from them.
proc qc_knobs_declare {kv} {
    foreach {n d} $kv {
        if {[info exists ::QC_KNOBS] && [dict exists $::QC_KNOBS $n] && [dict get $::QC_KNOBS $n] ne $d} {
            error "qc_knobs_declare: $n declared with default '[dict get $::QC_KNOBS $n]' and '$d'"
        }
        dict set ::QC_KNOBS $n $d
    }
}
proc qc_knob {n} {
    if {![info exists ::QC_KNOBS] || ![dict exists $::QC_KNOBS $n]} { error "qc_knob: $n is not a declared knob (qc_knobs_declare)" }
    if {[info exists ::env($n)] && $::env($n) ne ""} { return $::env($n) }
    return [dict get $::QC_KNOBS $n]
}
proc qc_knobs_record {file} {
    set f [open $file a]
    if {[info exists ::QC_KNOBS]} {
        foreach n [lsort [dict keys $::QC_KNOBS]] {
            puts $f "# knob $n [list [qc_knob $n]] [expr {[info exists ::env($n)] && $::env($n) ne "" ? "env" : "default"}]"
        }
    }
    foreach k [lsort [array names ::QC_RECORD]] { puts $f "# $k [uplevel #0 $::QC_RECORD($k)]" }
    close $f
}
