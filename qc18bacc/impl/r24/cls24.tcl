# R24 (results/r24.md): setup classes of a repaired hub checkpoint = impl/r21/sta_cls.tcl (QB_DB, QB21_PROP 1: R21_CLS
# lines in2out / in2reg / reg2out / reg2reg + per IO class) plus the top reg2reg start -> end groups (instance names with
# indices / digits collapsed): R24_GRP lines (violating endpoints, worst ns).
rename exit qb24_exit
proc exit {args} {}
source $::env(QC_FLOW)/../../qc18bacc/impl/r21/sta_cls.tcl
proc qb24_stem {pin} {
    set n [get_full_name $pin]; set i [string last / $n]; if {$i > 0} { set n [string range $n 0 [expr {$i - 1}]] }
    return [regsub -all {_?[0-9]+_?} $n N]
}
set ps [find_timing_paths -path_delay max -group_count 1000000 -endpoint_count 1 -slack_max 0 -from [all_registers] -to [all_registers]]
array set G {}
foreach pe $ps {
    set k "[qb24_stem [get_property $pe startpoint]] -> [qb24_stem [get_property $pe endpoint]]"
    set s [get_property $pe slack]
    if {![info exists G($k)]} { set G($k) [list 0 $s] }
    lassign $G($k) c w; set G($k) [list [incr c] [expr {min($w, $s)}]]
}
set ks [lsort -command {apply {{a b} {expr {[lindex $::G($b) 0] - [lindex $::G($a) 0]}}}} [array names G]]
foreach k [lrange $ks 0 4] { puts "R24_GRP reg2reg $k endpoints [lindex $G($k) 0] worst [lindex $G($k) 1]" }
set kw [lsort -command {apply {{a b} {expr {[lindex $::G($a) 1] < [lindex $::G($b) 1] ? -1 : 1}}}} [array names G]]
foreach k [lrange $kw 0 2] { puts "R24_GRPW reg2reg $k endpoints [lindex $G($k) 0] worst [lindex $G($k) 1]" }
qb24_exit
