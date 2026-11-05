# Hard macros (e.g. SRAM: LEF + lib, no GDS).  Nothing happens for a design without block instances.
#   MACRO_PLACE  list of {inst x_um y_um orient}: fixed placement (lower-left origin, orient R0 / MX / MY / R180)
#   MACRO_AUTO   1 = place the remaining macros with macro_placement (halo MACRO_HALO)
#   MACRO_HALO   {x y} um keep-out; rows under macros + halo are cut (cut_rows) when no tapcell is used
set ::QC_MACROS [qc_macros]
if {[llength $::QC_MACROS]} {
    set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set placed {}
    foreach m [p MACRO_PLACE] {
        lassign $m name x y orient
        set inst [[ord::get_db_block] findInst $name]
        if {$inst eq "NULL"} { error "MACRO_PLACE: no instance $name" }
        $inst setOrient [expr {$orient eq "" ? "R0" : $orient}]
        $inst setLocation [expr {round($x * $u)}] [expr {round($y * $u)}]
        $inst setPlacementStatus FIRM
        lappend placed $name
    }
    if {[p MACRO_AUTO] && [llength $placed] < [llength $::QC_MACROS]} {
        macro_placement -halo [p MACRO_HALO]
    }
    if {$::QC_PNR_TAPCELL eq ""} {
        cut_rows -halo_width_x [lindex [p MACRO_HALO] 0] -halo_width_y [lindex [p MACRO_HALO] 1]
    }
    qc_log "macros: [llength $::QC_MACROS] ([llength $placed] fixed by MACRO_PLACE)"
}
