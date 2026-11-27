# Routing (crosstalk-driven global / track routing, feedthrough NDR: qb_route_setup,
# qb_feedthru_ndr, R74): kit antenna rules (Milkyway clf antennaRule_n65_<n>lm.tcl, read in ICC2 syntax), diodes ANTENNA, route_auto,
# route_opt (MCMM setup / hold / DRV) twice, standard-cell decap + filler cells (site/pnr.tcl), route closure + hard gate
# (common.tcl qb_route_close, R92: route_detail on the DRCs the capped detail routes of route_auto / route_opt leave, then
# check_routes / check_lvs -check_child_cells all 0 or the step fails), legality gate (common.tcl qb_legality, R107).
# Block label cts -> route.  route_opt fixes hold (R55: 122 ropt_h_inst buffers, 142 -> 0 func_ff hold violators before its
# ECO routing) against the parasitics before it ECO-routes its own changes; that ECO routing leaves ps-level hold misses
# (R55: 70, WHV 2.4 ps).  The second, incremental route_opt (Synopsys RM) re-optimises on the routed parasitics.
# qb_io_load after route_auto, after the first route_opt and after the route closure that follows the last one (R84, R92):
# the layout-dependent IO loads (column act_o = own act[b] net) from the routed nets; route_opt sizes / buffers /
# re-routes the act nets and a closure pass re-routes too, so the load of the pass before is stale.
# route_opt also fixes clock-net max_transition / max_capacitance on the routed parasitics (post-route clock DRC fixing,
# route_opt.flow.enable_ccd_clock_drc_fixing always_on; CCD / useful skew stays off): signal routing changes the clock
# nets' coupling after CTS, and clock_opt final_opto and PrimeTime never change clock nets.  It sizes clock buffers /
# inverters (R65 [M]: r65 ctsbuf_net_82788, 1 attempted, 1 committed); it does not resize clock gates (R75 [M], cts.tcl),
# which the sign-off ECO's clock-network pass fixes (signoff/pt/drv_eco.tcl).
# qb_io_lat (compute_clock_latency) before each route_opt: the IO paths of a propagated clock are timed with the I/O
# latency the command sets (median sink latency, derated late / early per check: common.tcl), which cts.tcl computed on
# CTS estimates (R63 [M] ss 0.815 ns vs routed PT p50 0.724).
source [file dirname [info script]]/common.tcl
qb_open cts route
# pre-route correlation off (R98; common.tcl qb_preroute): routed parasitics and the SDC setup uncertainty from here on
qb_preroute off
qb_route_setup
qb_feedthru_ndr
route_auto
qb_io_load
set_app_options -name route_opt.flow.enable_ccd_clock_drc_fixing -value always_on
qb_io_lat route1
route_opt
qb_io_load
qb_io_lat route2
route_opt
qb_fillers
qb_route_close route
qb_io_load
# legality of the layout written out (R107; hunt round 11 on d1978e1: route_opt sizes / inserts cells and the fillers
# fill the rows after the cts gate, and nothing checked them; common.tcl qb_legality, gated by signoff/verdict.py)
qb_legality route
qb_isolate_report route
qb_qor route
qb_done route
