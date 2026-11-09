# place: global placement (timing / routability driven), electrical repair (slew, cap, fanout, tie fanout),
# detailed placement.  Hook PRE_PLACE_TCL.
if {[p PRE_PLACE_TCL] ne ""} { source [p PRE_PLACE_TCL] }
set gpl [list -density [p PLACE_DENSITY] -pad_left [p PLACE_PAD] -pad_right [p PLACE_PAD]]
if {[p TIMING_DRIVEN]}      { lappend gpl -timing_driven }
if {[p ROUTABILITY_DRIVEN]} { lappend gpl -routability_driven }
lappend gpl {*}[p GPL_ARGS]
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
global_placement {*}$gpl
estimate_parasitics -placement
foreach t [list $::QC_PNR_TIEHI $::QC_PNR_TIELO] { repair_tie_fanout -separation 2 [join $t /] }
# REPAIR_DESIGN auto: repair only the nets with DRV violations (qc_repair_drv, DC sizing kept elsewhere);
# 1: plain repair_design (also resizes every other driver towards a target slew); 0: none
set ndrv [expr {[sta::max_slew_violation_count] + [sta::max_capacitance_violation_count] + [sta::max_fanout_violation_count]}]
qc_log "drv violations after global placement: $ndrv"
if {[p REPAIR_DESIGN] eq "1"} {
    repair_design -max_utilization [p MAX_UTIL]
} elseif {[p REPAIR_DESIGN] eq "auto" && $ndrv > 0} {
    qc_repair_drv
}
detailed_placement
check_placement
estimate_parasitics -placement
qc_report place
qc_summary "place [qc_util]"
qc_summary "place [join [qc_timing_lines place] { | }]"
