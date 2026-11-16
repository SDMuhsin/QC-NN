# impl/r6c test of spread3.tcl (read-only on db/place.odb, nothing written): record every cell except the repair
# buffers (they become the movers), run spread3, report the DETOUR metric of probe_rows.tcl afterwards.
proc qb_env {n d} { return [expr {[info exists ::env($n)] ? $::env($n) : $d}] }
proc qc_log {m} { puts "QC_PNR $m" }
read_db $::env(QB_RUN)/db/place.odb
array set ::QB6_M {}
foreach i [[ord::get_db_block] getInsts] { if {![[$i getMaster] isBlock] && ![regexp {^(wire|max_length|load_slew|max_cap|fanout)\d+} [$i getName]]} { set ::QB6_M($i) [[$i getMaster] getName] } }
source $::env(QB_R6C)/spread3.tcl
qb6c_spread3
