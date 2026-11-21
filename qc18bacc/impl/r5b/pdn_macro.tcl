# MACRO_PDN_TCL of impl/r5b/chip.cfg.  Column blocks: M7 VDD / VSS pins to the M8 straps (impl/hard/col_pdn_macro.tcl
# scheme).  ARM macros (as qc18acc/pnr/pdn_macro.tcl): VDDCE / VDDPE -> VDD, VSSE -> VSS; sram_sp_adv (descriptors,
# FC) rings M3 / M4: M4 -> M7; rf_sp_adv / rf_2p_adv (weights, S, maps, image, params) rings M2 / M3: macro M4 straps,
# M3 -> M4 -> M7 (QB_PDN_BLK / _SRAM / _RF 0: skip a grid, for tests).  The core M7 straps run over the ARM macros (they obstruct M1-M4 only).
add_global_connection -net $::QC_PNR_PWR -pin_pattern {^VDD[CP]E$} -power
add_global_connection -net $::QC_PNR_GND -pin_pattern {^VSSE$} -ground
global_connect
set _blk {}; set _sram {}; set _rf {}
foreach i [qc_macros] {
    set mn [[$i getMaster] getName]
    # R35 opt-in QB_PDN_BLKX: more hard-block masters on the block grid (M7 -> M8 connect only, no macro stripes)
    if {$mn eq "qb_col_blk" || $mn in [qb_env QB_PDN_BLKX {}]} { set l _blk } elseif {[string match qb_d_* $mn] || [string match qb_f_3232* $mn]} { set l _sram } else { set l _rf }
    if {[lsearch -exact [set $l] $mn] < 0} { lappend $l $mn }
}
qc_log "pdn_macro: masters blocks $_blk sram $_sram rf $_rf"
if {[qb_env QB_PDN_BLK 1]} {
define_pdn_grid -macro -cells $_blk -name macro_blk -halo {0 0} -grid_over_boundary
add_pdn_connect -grid macro_blk -layers {M7 M8} {*}[qb_env QB_V78 {}]
}
if {[qb_env QB_PDN_SRAM 1]} {
define_pdn_grid -macro -cells $_sram -name macro_sram -halo [p MACRO_HALO] -grid_over_boundary
# R43 opt-in QB43_SRAM_CONN (list of layer pairs; default = the two below): r39_v DR / LVS shorts at the R90 u_ds
# came from the M4 -> M8 stacks (2.94-um VIA4-7 arrays through M5-M7 under every 3-um M8 strap); "{M3 M7}" connects
# the R90 ring's vertical M3 sides to the core M7 straps instead (0.8-um stacks, as the other macros' M4 -> M7)
foreach _c [qb_env QB43_SRAM_CONN {{M4 M7} {M4 M8}}] { add_pdn_connect -grid macro_sram -layers $_c }
}
if {[qb_env QB_PDN_RF 1]} {
define_pdn_grid -macro -cells $_rf -name macro_rf -halo [p MACRO_HALO] -grid_over_boundary
# R43 opt-in QB43_RF_M4OFF [10.0]: offset of the rf macro M4 straps (r39_v: the strap at qb_w x 230 covers EMA[1] ->
# NS Metal at its pin in every qb_w, reproduced alone in impl/r43/ema43.tcl)
add_pdn_stripe -grid macro_rf -layer M4 -width 1.0 -pitch 20.0 -offset [qb_env QB43_RF_M4OFF 10.0]
add_pdn_connect -grid macro_rf -layers {M3 M4}
add_pdn_connect -grid macro_rf -layers {M4 M7}
}
