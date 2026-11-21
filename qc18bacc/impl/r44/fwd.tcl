# forward dump of an ICG's gated subtree (env ODB, ICGS): every buffer with location and its sink count / sink x-range
read_db $::env(ODB)
set blk [ord::get_db_block]
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
proc loc {i} { global u; set b [$i getBBox]; return [format "(%.0f,%.0f)" [expr {[$b xMin]/$u}] [expr {[$b yMin]/$u}]] }
proc walk {inst depth} {
  global u
  foreach it [$inst getITerms] {
    if {![$it isOutputSignal] || [$it getNet] eq "NULL"} continue
    set net [$it getNet]; set fl {}; set bufs {}
    foreach s [$net getITerms] { if {[$s getInst] eq $inst} continue
      set m [[[$s getInst] getMaster] getName]
      if {[string match CKB* $m] || [string match BUFF* $m] || [string match CKLNQD* $m]} { lappend bufs [$s getInst] } else { lappend fl [$s getInst] } }
    set xs {}; foreach f $fl { set b [$f getBBox]; lappend xs [expr {round([$b xMin]/$u)}] }
    set xs [lsort -integer $xs]
    puts [format "FW %s%s %s %s -> %d flops x %s..%s, %d bufs" [string repeat "  " $depth] [$inst getName] [[$inst getMaster] getName] [loc $inst] [llength $fl] [lindex $xs 0] [lindex $xs end] [llength $bufs]]
    foreach b $bufs { if {$depth < 12} { walk $b [expr {$depth+1}] } }
  }
}
foreach g $::env(ICGS) { set i [$blk findInst $g]; if {$i eq "NULL"} { puts "FW $g missing"; continue }; walk $i 0 }
foreach i [$blk getInsts] { if {[string match -nocase *clone* [$i getName]] && [string match CKLNQD* [[$i getMaster] getName]]} { puts "FWCLONE [$i getName] [loc $i]"; walk $i 1 } }
