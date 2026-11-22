# Routing: kit antenna rules (Milkyway clf antennaRule_n65_<n>lm.tcl, read in ICC2 syntax), diodes ANTENNA, route_auto,
# route_opt (MCMM setup / hold / DRV), standard-cell decap + filler cells (site/pnr.tcl), check_routes / check_lvs.
# Block label cts -> route.
source [file dirname [info script]]/common.tcl
qb_open cts route
# the kit file is ICC1 Tcl: drop the Milkyway library argument and its set_parameter / current_mw_lib / report lines
proc qb_antenna_rules {f} {
    set fh [open $f]; set t [read $fh]; close $fh
    regsub -all -line {^\s*(set_parameter|set lib|remove_antenna_rules|report_antenna_rules).*$} $t {} t
    regsub -all {(define_antenna_(?:layer_)?rule)\s+\$lib} $t {\1} t
    uplevel #0 $t
}
set nm [regexp -inline {[0-9]+lm} [file tail $::QC_TF]]
qb_antenna_rules $::QC_MW/clf/antennaRule_n65_$nm.tcl
redirect $::R/rpt/route_antenna_rules.rpt { report_antenna_rules }
set_app_options -name route.detail.antenna -value true
set_app_options -name route.detail.insert_diodes_during_routing -value true
set_app_options -name route.detail.diode_libcell_names -value [lindex $::QC_PNR_DIODE 0]
foreach o {route.global.timing_driven route.track.timing_driven route.detail.timing_driven} { set_app_options -name $o -value true }
route_auto
route_opt
# decaps (they carry M1) first and removed where they violate, then the metal-free FILL* close every remaining gap
# (R54 ran both in one create_stdcell_fillers: the removed DCAPs left empty gaps, Calibre NW.S.1 / OD2.S.5 27 004)
foreach {lc chk} [list $::QC_PNR_DCAP 1 $::QC_PNR_FILL 0] {
    set fl {}; foreach c $lc { lappend fl */$c }
    create_stdcell_fillers -lib_cells [get_lib_cells $fl]
    connect_pg_net -automatic
    if {$chk} { remove_stdcell_fillers_with_violation }
}
redirect $::R/rpt/route_check_routes.rpt { check_routes }
redirect $::R/rpt/route_check_lvs.rpt { check_lvs -max_errors 0 }
foreach r {check_routes check_lvs} {
    set t [exec cat $::R/rpt/route_$r.rpt]
    foreach l [split $t "\n"] { if {[regexp -nocase {total number|total.*(error|violation)|open|short} $l]} { qb_line "route $r [string trim $l]" } }
}
qb_qor route
qb_done route
