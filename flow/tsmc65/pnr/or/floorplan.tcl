# floorplan: die / core from utilisation (or explicit areas), tracks, macros (fixed list or automatic), IO pins,
# tie cells.  Hooks: FLOORPLAN_TCL (after rows / macros), PIN_TCL (replaces place_pins).
if {[llength [p DIE_AREA]] == 4 && [llength [p CORE_AREA]] == 4} {
    initialize_floorplan -site $::QC_PNR_SITE -die_area [p DIE_AREA] -core_area [p CORE_AREA]
} else {
    initialize_floorplan -site $::QC_PNR_SITE -utilization [expr {100.0 * [p CORE_UTIL]}] \
        -aspect_ratio [p ASPECT] -core_space [p CORE_MARGIN]
}
make_tracks
source $::env(QC_FLOW)/pnr/or/macros.tcl
if {[p FLOORPLAN_TCL] ne ""} { source [p FLOORPLAN_TCL] }
qc_tie_constants
if {$::QC_PNR_TAPCELL ne ""} {
    tapcell -tapcell_master [lindex $::QC_PNR_TAPCELL 0] -distance [lindex $::QC_PNR_TAPCELL 1] \
        -halo_width_x [lindex [p MACRO_HALO] 0] -halo_width_y [lindex [p MACRO_HALO] 1]
}
if {[p PIN_TCL] ne ""} {
    source [p PIN_TCL]
} else {
    place_pins -hor_layers $::QC_PNR_PIN_H -ver_layers $::QC_PNR_PIN_V -min_distance 2 -min_distance_in_tracks
}
qc_summary "floorplan [qc_util]"
