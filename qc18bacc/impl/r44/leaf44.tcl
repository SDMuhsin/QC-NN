# R44: latency per leaf driver of the two late g_wbc subtrees (QB_DB, placement parasitics, tt)
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env QB_DB cts]
set_propagated_clock [all_clocks]
estimate_parasitics -placement
set blk [ord::get_db_block]
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
proc arr {pin} { foreach pr {arrival_max_rise max_rise_arrival} { if {![catch {get_property $pin $pr} v] && $v ne "" && ![string match -nocase *inf* $v]} { if {$v < 1e-6} {set v [expr {$v*1e9}]}; return [format %.3f $v] } }; return "-" }
foreach g {u_top_clk_gate_g_wbc_ha_reg_7__7_/latch u_top_clk_gate_g_wbc_hdo_reg_7__6_/latch} {
  puts "LF ICG $g CP [arr [get_pins $g/CP]] Q [arr [get_pins $g/Q]]"
  set todo [list [$blk findInst $g]]
  while {[llength $todo]} {
    set inst [lindex $todo 0]; set todo [lrange $todo 1 end]
    foreach it [$inst getITerms] { if {![$it isOutputSignal] || [$it getNet] eq "NULL"} continue
      set fl {}
      foreach s [[$it getNet] getITerms] { if {[$s getInst] eq $inst} continue
        set m [[[$s getInst] getMaster] getName]
        if {[string match CKB* $m] || [string match BUFF* $m]} { lappend todo [$s getInst] } else { lappend fl [$s getInst] } }
      if {[llength $fl]} { set as {}; foreach f $fl { lappend as [arr [get_pins [$f getName]/CP]] }
        set b [$inst getBBox]; set as [lsort -real $as]
        puts [format "LF   leaf %-36s (%.0f,%.0f) %2d flops latency %s..%s" [$inst getName] [expr {[$b xMin]/$u}] [expr {[$b yMin]/$u}] [llength $fl] [lindex $as 0] [lindex $as end]] }
    }
  }
}
exit
