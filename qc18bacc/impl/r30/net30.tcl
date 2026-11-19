# R30 probe (read-only): netlist / route-resource statistics of a run's db (R30_DB, default grt).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R30_DB grt]
set blk [ord::get_db_block]; set tech [ord::get_db_tech]; set u [expr {double([$blk getDefUnits])}]
# tracks vs LEF pitch / offset
foreach tg [$blk getTrackGrids] {
  set l [$tg getTechLayer]
  set xs [$tg getGridX]; set ys [$tg getGridY]
  puts [format "R30T %s dir %s lefpitch %.3f lefoff x %.3f y %.3f width %.3f | nx %d x0 %.3f dx %.3f | ny %d y0 %.3f dy %.3f" \
    [$l getName] [$l getDirection] [expr {[$l getPitch]/$u}] [expr {[$l getOffsetX]/$u}] [expr {[$l getOffsetY]/$u}] [expr {[$l getWidth]/$u}] \
    [llength $xs] [expr {[llength $xs]?[lindex $xs 0]/$u:-1}] [expr {[llength $xs]>1?([lindex $xs 1]-[lindex $xs 0])/$u:-1}] \
    [llength $ys] [expr {[llength $ys]?[lindex $ys 0]/$u:-1}] [expr {[llength $ys]>1?([lindex $ys 1]-[lindex $ys 0])/$u:-1}]]
}
# rows
set r0 [lindex [$blk getRows] 0]
puts "R30R rows [llength [$blk getRows]] site [[$r0 getSite] getName] h [expr {[[$r0 getSite] getHeight]/$u}] w [expr {[[$r0 getSite] getWidth]/$u}] orig [$r0 getOrigin]"
# nets
array set ::r30c {}
set nund 0; set nundp 0; set hund 0.0; set tie 0; set tiep 0
foreach n [$blk getNets] {
  set st [$n getSigType]; incr ::r30c(st_$st)
  if {$st ne "SIGNAL" && $st ne "CLOCK"} continue
  set its [$n getITerms]; set bts [$n getBTerms]
  set np [expr {[llength $its] + [llength $bts]}]
  set drv 0
  foreach it $its { if {[$it isOutputSignal]} { set drv 1; break } }
  foreach bt $bts { if {[$bt getIoType] eq "INPUT" || [$bt getIoType] eq "INOUT"} { set drv 1 } }
  set k [expr {$np <= 1 ? "p1" : ($np <= 2 ? "p2" : ($np <= 5 ? "p3_5" : ($np <= 20 ? "p6_20" : ($np <= 100 ? "p21_100" : "p100+"))))}]
  incr ::r30c($k)
  if {!$drv && $np >= 2} { incr nund; incr nundp $np
     if {$nund <= 15} { puts "R30U undriven [$n getName] pins $np" } }
}
foreach i [$blk getInsts] { set m [[$i getMaster] getName]; if {$m eq "TIEH" || $m eq "TIEL"} { incr tie } ; incr ::r30c(m_[[$i getMaster] getType]) }
puts "R30N [array get ::r30c]"
puts "R30N undriven_multi_pin_nets $nund pins $nundp tie_cells $tie"
exit
