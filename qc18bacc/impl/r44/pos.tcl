# usage: openroad -exit pos.tcl  (env ODB)
read_db $::env(ODB)
set blk [ord::get_db_block]
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
proc loc {i} { global u; set b [$i getBBox]; return [format "(%.0f,%.0f)" [expr {[$b xMin]/$u}] [expr {[$b yMin]/$u}]] }
foreach n {u_top_clk_gate_g_wbc_ha_reg_7__7_/latch u_top_g_wbc_ha_reg_7__7__102_ u_top_g_wbc_ha_reg_7__7__0_ u_top_g_wbc_ha_reg_7__7__60_ clkbuf_0_u_top_net564732 clkbuf_2_1_0_u_top_net564732 wire18} {
  set i [$blk findInst $n]
  if {$i eq "NULL"} { puts "POS $n missing" } else { puts "POS $n [loc $i] [[$i getMaster] getName]" }
}
# ICG Q net: sink bbox
set i [$blk findInst u_top_clk_gate_g_wbc_ha_reg_7__7_/latch]
set q [[$i findITerm Q] getNet]
puts "QNET [$q getName]"
foreach it [$q getITerms] { puts "  QSINK [[$it getInst] getName] [loc [$it getInst]]" }
