# per-ICG gated-sink bbox at placement (env ODB); prints histogram + worst 25 and sink-name prefix groups
read_db $::env(ODB)
set blk [ord::get_db_block]
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set rows {}
foreach i [$blk getInsts] {
  if {![string match CKLNQD* [[$i getMaster] getName]]} continue
  set it [$i findITerm Q]; if {$it eq "NULL" || [$it getNet] eq "NULL"} continue
  set x0 1e12; set y0 1e12; set x1 -1e12; set y1 -1e12; set n 0; array unset pre
  foreach s [[$it getNet] getITerms] {
    if {[$s getInst] eq $i} continue
    set b [[$s getInst] getBBox]
    set x [expr {[$b xMin]/$u}]; set y [expr {[$b yMin]/$u}]
    set x0 [expr {min($x0,$x)}]; set x1 [expr {max($x1,$x)}]; set y0 [expr {min($y0,$y)}]; set y1 [expr {max($y1,$y)}]; incr n
    regsub {_reg.*$} [[$s getInst] getName] {} p; set pre($p) 1
  }
  if {$n == 0} continue
  lappend rows [list [expr {($x1-$x0)+($y1-$y0)}] $n [$i getName] [array names pre]]
}
set rows [lsort -real -decreasing -index 0 $rows]
set h(0-200) 0; set h(200-500) 0; set h(500-1000) 0; set h(>1000) 0; set mixed 0
foreach r $rows { set d [lindex $r 0]
  if {$d < 200} {incr h(0-200)} elseif {$d < 500} {incr h(200-500)} elseif {$d < 1000} {incr h(500-1000)} else {incr h(>1000)}
  if {[llength [lindex $r 3]] > 1} {incr mixed} }
puts "ICGBB n [llength $rows] hpwl_um 0-200 $h(0-200) 200-500 $h(200-500) 500-1000 $h(500-1000) >1000 $h(>1000) multi-prefix $mixed"
foreach r [lrange $rows 0 24] { puts [format "ICGW %7.0f %4d %s %s" {*}$r] }
