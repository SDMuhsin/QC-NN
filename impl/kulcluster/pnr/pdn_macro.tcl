# Macro PDN of the KUL cluster (MACRO_PDN_TCL, sourced after the core grid definition, before pdngen).
# ARM RF PG rings: VDDPE (periphery) and VDDCE (core) -> VDD, VSSE -> VSS, on M3 (horizontal) and M2 (vertical),
# signal pins on M1-M3 just inside the ring.  M6 straps over each macro, via stacks down to the M3 ring segments
# (away from the signal pins, M4 stays free for pin access) and up to the M7 core straps.
add_global_connection -net $::QC_PNR_PWR -pin_pattern {^VDD[CP]E$} -power
add_global_connection -net $::QC_PNR_GND -pin_pattern {^VSSE$} -ground
global_connect
define_pdn_grid -macro -default -name macro -halo [p MACRO_HALO]
add_pdn_stripe -grid macro -layer M6 -width 1.0 -pitch 40.0 -offset 10.0
add_pdn_connect -grid macro -layers {M3 M6}
add_pdn_connect -grid macro -layers [list M6 [p PDN_H_LAYER]]
