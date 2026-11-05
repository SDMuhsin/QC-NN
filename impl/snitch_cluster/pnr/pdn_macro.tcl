# Macro PDN of the Snitch FP cluster (MACRO_PDN_TCL, sourced after the core grid definition, before pdngen).
# ARM PG rings: VDDPE (periphery) and VDDCE (core) -> VDD, VSSE -> VSS.  qc_sp_1024x64m8: ring on M3 (horizontal)
# and M4 (vertical), blocks M1-M4; qc_rf_16x128m1: ring on M3 / M2, blocks M1-M3.  M6 straps over each macro with
# via stacks down to the M3 ring segments (upper / lower edge, outside the signal pin rows) and up to the M7 core
# straps.  (Same scheme as impl/kulcluster/pnr/pdn_macro.tcl.)
add_global_connection -net $::QC_PNR_PWR -pin_pattern {^VDD[CP]E$} -power
add_global_connection -net $::QC_PNR_GND -pin_pattern {^VSSE$} -ground
global_connect
define_pdn_grid -macro -default -name macro -halo [p MACRO_HALO]
add_pdn_stripe -grid macro -layer M6 -width 1.0 -pitch 40.0 -offset 10.0
add_pdn_connect -grid macro -layers {M3 M6}
add_pdn_connect -grid macro -layers [list M6 [p PDN_H_LAYER]]
