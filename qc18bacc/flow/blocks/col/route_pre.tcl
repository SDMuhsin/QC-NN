# PRE_ROUTE_TCL of blocks/col/col.cfg: post-CTS repair (repair/post_cts.tcl, IO budget shifted by the measured insertion
# delay), the per-layer GRT adjustment QB15_GADJ_L (route/gadj_layers.tcl) for the flow's global route, and the kit
# min-step / EOL rules for the route step's detailed_route (route/drc_rules.tcl).
source $::QBF/repair/post_cts.tcl
source $::QBF/route/gadj_layers.tcl
source $::QBF/route/drc_rules.tcl
