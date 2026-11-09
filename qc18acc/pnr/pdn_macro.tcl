# Macro PDN of QC18-ACC (MACRO_PDN_TCL, after the core grid definition, before pdngen).
# ARM sram_sp_adv / rf_sp_adv PG rings: VDDPE (periphery) and VDDCE (core) -> VDD, VSSE -> VSS, ring on M3 (horizontal) /
# M4 (vertical) for the SRAMs (M2 / M3 for the RF).  The core M7 straps run over the macros (the macros obstruct M1-M4
# only); via stacks M4 -> M7 where a strap crosses a vertical M4 ring / strap segment of its net.  The RF (descriptor)
# has its ring on M3 (horizontal) / M2: macro M4 straps (the RF obstructs M1-M3 only), M3 -> M4 -> M7.
add_global_connection -net $::QC_PNR_PWR -pin_pattern {^VDD[CP]E$} -power
add_global_connection -net $::QC_PNR_GND -pin_pattern {^VSSE$} -ground
global_connect
set qa_sram {}; set qa_rf {}
foreach i [qc_macros] { if {[string match qa_dsc* [[$i getMaster] getName]]} { lappend qa_rf [$i getName] } else { lappend qa_sram [$i getName] } }
define_pdn_grid -macro -instances $qa_sram -name macro_sram -halo [p MACRO_HALO] -grid_over_boundary
add_pdn_connect -grid macro_sram -layers [list M4 [p PDN_H_LAYER]]
define_pdn_grid -macro -instances $qa_rf -name macro_rf -halo [p MACRO_HALO] -grid_over_boundary
add_pdn_stripe -grid macro_rf -layer M4 -width 1.0 -pitch 20.0 -offset 10.0
add_pdn_connect -grid macro_rf -layers {M3 M4}
add_pdn_connect -grid macro_rf -layers [list M4 [p PDN_H_LAYER]]
# global M8 mesh over the whole core (the outer weight / param tiers have no standard-cell rows, so their M7 straps
# only reach the core grid through M8): vertical 2.0 um straps, pitch 60 um
add_pdn_stripe -grid core -layer M8 -width 2.0 -pitch 60.0 -offset 30.0
add_pdn_connect -grid core -layers [list [p PDN_H_LAYER] M8]
