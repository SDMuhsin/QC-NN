# MACRO_PDN_TCL of impl/r10b/hub.cfg: impl/r5b/pdn_macro.tcl, except the params macros (qb_p_*) in their own grid with
# M7 stripes (pitch / offset of the core M7) + M7-M8 vias: with the R10b params row (9 macros across the whole core
# width, 2.6-um gaps) pdngen leaves no core M7 stripe over the row (VDD: no M7 / no M4-M7 via below y 160, r10b_oA
# PSM-0069 on all 9 macros): core shapes are cut out of macro grid regions (macro + halo), so no core M8 strap
# crosses the row and its M7 floats.  The params grid carries its own M7 + M8 (core pitch / offset: its M8 straps
# meet the core M8 straps at the row's halo edge).
# MACRO_PDN_TCL of impl/r5b/chip.cfg.  Column blocks: M7 VDD / VSS pins to the M8 straps (impl/hard/col_pdn_macro.tcl
# scheme).  ARM macros (as qc18acc/pnr/pdn_macro.tcl): VDDCE / VDDPE -> VDD, VSSE -> VSS; sram_sp_adv (descriptors,
# FC) rings M3 / M4: M4 -> M7; rf_sp_adv / rf_2p_adv (weights, S, maps, image, params) rings M2 / M3: macro M4 straps,
# M3 -> M4 -> M7 (QB_PDN_BLK / _SRAM / _RF 0: skip a grid, for tests).  The core M7 straps run over the ARM macros (they obstruct M1-M4 only).
add_global_connection -net $::QC_PNR_PWR -pin_pattern {^VDD[CP]E$} -power
add_global_connection -net $::QC_PNR_GND -pin_pattern {^VSSE$} -ground
global_connect
set _blk {}; set _sram {}; set _rf {}; set _prm {}
foreach i [qc_macros] {
    set mn [[$i getMaster] getName]
    if {$mn eq "qb_col_blk"} { set l _blk } elseif {[string match qb_d_* $mn] || [string match qb_f_3232* $mn]} { set l _sram } else { set l _rf }
    if {[string match qb_p_* $mn]} { set l _prm }
    if {[lsearch -exact [set $l] $mn] < 0} { lappend $l $mn }
}
qc_log "pdn_macro: masters blocks $_blk sram $_sram rf $_rf"
if {[qb_env QB_PDN_BLK 1]} {
define_pdn_grid -macro -cells $_blk -name macro_blk -halo {0 0} -grid_over_boundary
add_pdn_connect -grid macro_blk -layers {M7 M8} {*}[qb_env QB_V78 {}]
}
if {[qb_env QB_PDN_SRAM 1]} {
define_pdn_grid -macro -cells $_sram -name macro_sram -halo [p MACRO_HALO] -grid_over_boundary
add_pdn_connect -grid macro_sram -layers {M4 M7}
add_pdn_connect -grid macro_sram -layers {M4 M8}    ;# R90 macros (FC): the ring M4 runs horizontally, under the M8 straps
}
if {[qb_env QB_PDN_RF 1]} {
define_pdn_grid -macro -cells $_rf -name macro_rf -halo [p MACRO_HALO] -grid_over_boundary
add_pdn_stripe -grid macro_rf -layer M4 -width 1.0 -pitch 20.0 -offset 10.0
add_pdn_connect -grid macro_rf -layers {M3 M4}
add_pdn_connect -grid macro_rf -layers {M4 M7}
}
if {[llength $_prm]} {
define_pdn_grid -macro -cells $_prm -name macro_prm -halo [p MACRO_HALO] -grid_over_boundary
add_pdn_stripe -grid macro_prm -layer M4 -width 1.0 -pitch 20.0 -offset 10.0
add_pdn_stripe -grid macro_prm -layer M7 -width 0.8 -pitch 30.0 -offset 5.0
add_pdn_connect -grid macro_prm -layers {M3 M4}
add_pdn_connect -grid macro_prm -layers {M4 M7}
add_pdn_stripe -grid macro_prm -layer M8 -width [qb_env QB_M8W 3.0] -pitch 40.0 -offset 10.0
add_pdn_connect -grid macro_prm -layers {M7 M8}
}
