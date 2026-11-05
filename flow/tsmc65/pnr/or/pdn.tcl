# pdn: global connections, M1 followpin rails + two strap layers (PDN_V_* / PDN_H_*); PDN_TCL replaces the grid
# definition.  Macros: MACRO_PDN_TCL defines their grids (define_pdn_grid -macro ...), default: connect the
# PDN_H_LAYER straps to the macro PG pins on MACRO_PIN_LAYER.
add_global_connection -net $::QC_PNR_PWR -pin_pattern "^$::QC_PNR_PWR\$" -power
add_global_connection -net $::QC_PNR_GND -pin_pattern "^$::QC_PNR_GND\$" -ground
global_connect
set_voltage_domain -power $::QC_PNR_PWR -ground $::QC_PNR_GND
if {[p PDN_TCL] ne ""} {
    source [p PDN_TCL]
} else {
    define_pdn_grid -name core
    add_pdn_stripe -grid core -layer $::QC_PNR_RAIL -width [p PDN_RAIL_W] -followpins
    add_pdn_stripe -grid core -layer [p PDN_V_LAYER] -width [p PDN_V_W] -pitch [p PDN_V_PITCH] -offset [p PDN_V_OFFSET]
    add_pdn_stripe -grid core -layer [p PDN_H_LAYER] -width [p PDN_H_W] -pitch [p PDN_H_PITCH] -offset [p PDN_H_OFFSET]
    add_pdn_connect -grid core -layers [list $::QC_PNR_RAIL [p PDN_V_LAYER]]
    add_pdn_connect -grid core -layers [list [p PDN_V_LAYER] [p PDN_H_LAYER]]
}
if {[p MACRO_PDN_TCL] ne ""} {
    source [p MACRO_PDN_TCL]
} elseif {[llength [qc_macros]]} {
    # default macro grid: vias from the upper core strap layer down to the macro PG pins (MACRO_PIN_LAYER)
    define_pdn_grid -macro -default -name macro -halo [p MACRO_HALO] -grid_over_boundary
    add_pdn_connect -grid macro -layers [list [p MACRO_PIN_LAYER] [p PDN_H_LAYER]]
}
pdngen
# connectivity of the grid (PSM): every stripe and rail reaches the rest of its net
foreach n [list $::QC_PNR_PWR $::QC_PNR_GND] {
    if {[catch {check_power_grid -net $n} ok]} { set ok "error: $ok" }
    qc_summary "pdn $n check_power_grid $ok"
}
