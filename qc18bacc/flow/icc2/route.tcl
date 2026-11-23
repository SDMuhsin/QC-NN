# Routing: kit antenna rules (Milkyway clf antennaRule_n65_<n>lm.tcl, read in ICC2 syntax), diodes ANTENNA, route_auto,
# route_opt (MCMM setup / hold / DRV) twice, standard-cell decap + filler cells (site/pnr.tcl), check_routes / check_lvs.
# Block label cts -> route.  route_opt fixes hold (R55: 122 ropt_h_inst buffers, 142 -> 0 func_ff hold violators before its
# ECO routing) against the parasitics before it ECO-routes its own changes; that ECO routing leaves ps-level hold misses
# (R55: 70, WHV 2.4 ps).  The second, incremental route_opt (Synopsys RM) re-optimises on the routed parasitics.
# qb_io_load after route_auto: the layout-dependent IO loads (column act_o) from the routed nets.
# compute_clock_latency before each route_opt: the IO paths of a propagated clock are timed with the I/O latency the
# command sets (median sink latency), which cts.tcl computed on CTS estimates (R63 [M] ss 0.815 ns vs routed PT p50 0.724:
# ICC2 timed reg -> output 91 ps optimistic and input -> reg pessimistic against the sign-off IO budget shift L).
source [file dirname [info script]]/common.tcl
qb_open cts route
qb_route_setup
route_auto
qb_io_load
compute_clock_latency
route_opt
compute_clock_latency
route_opt
qb_fillers
qb_route_checks route
qb_qor route
qb_done route
