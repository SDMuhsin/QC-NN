# R30 probe (read-only): dont-touch nets / insts and long nets (HPWL) of a run's db (R30_DB [grt]).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
qc_read_liberty
read_db $::OUT/db/[qc_env R30_DB grt].odb
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]
set ndt 0; set idt 0; array set h {}
foreach n [$blk getNets] {
  if {[$n isDoNotTouch]} { incr ndt }
  if {[$n getSigType] ne "SIGNAL"} continue
  set xs {}; set ys {}
  foreach it [$n getITerms] { set b [$it getBBox]; lappend xs [$b xMin]; lappend ys [$b yMin] }
  foreach bt [$n getBTerms] { set b [$bt getBBox]; lappend xs [$b xMin]; lappend ys [$b yMin] }
  if {[llength $xs] < 2} continue
  set hp [expr {([tcl::mathfunc::max {*}$xs] - [tcl::mathfunc::min {*}$xs] + [tcl::mathfunc::max {*}$ys] - [tcl::mathfunc::min {*}$ys]) / $u}]
  set k [expr {$hp < 100 ? "a<100" : ($hp < 500 ? "b<500" : ($hp < 1000 ? "c<1000" : ($hp < 2000 ? "d<2000" : "e>=2000")))}]
  incr h($k)
}
foreach i [$blk getInsts] { if {[$i isDoNotTouch]} { incr idt } }
puts "R30DT dont_touch nets $ndt insts $idt hpwl [lsort [array get h]]"
exit
