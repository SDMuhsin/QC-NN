# Routing: kit antenna rules (Milkyway clf antennaRule_n65_<n>lm.tcl, read in ICC2 syntax), diodes ANTENNA, route_auto,
# route_opt (MCMM setup / hold / DRV) twice, standard-cell decap + filler cells (site/pnr.tcl), check_routes / check_lvs.
# Block label cts -> route.  route_opt fixes hold (R55: 122 ropt_h_inst buffers, 142 -> 0 func_ff hold violators before its
# ECO routing) against the parasitics before it ECO-routes its own changes; that ECO routing leaves ps-level hold misses
# (R55: 70, WHV 2.4 ps).  The second, incremental route_opt (Synopsys RM) re-optimises on the routed parasitics.
source [file dirname [info script]]/common.tcl
qb_open cts route
qb_route_setup
route_auto
route_opt
route_opt
qb_fillers
qb_route_checks route
qb_qor route
qb_done route
