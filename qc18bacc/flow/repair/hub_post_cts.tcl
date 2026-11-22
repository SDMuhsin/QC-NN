# Hub post-CTS repair sequence (QB_PC_HOOK of repair/post_cts.tcl, set by route/hub_route_pre.tcl; results/r24.md, r28.md):
# sourced after the IO delays and the qb_* procs of post_cts.tcl.  Setup repair, legalise, hold repair, legalise, then one
# more setup repair (+ hold repair where hold violations reappear), each legalisation followed by parasitics and a count
# line (repair/hub_post_cts.tcl mode fix with the plain legalisation, QB_RT_LOOPS 1).
qb_setup
qb_counts postcts_setup_repair
qb_legal postcts_setup_legal
qb_hold
qb_counts postcts_hold_repair_unlegal
qb_legal postcts_hold_legal
qb_setup
qb_counts postcts_setup1_repair
qb_legal postcts_setup1_legal
set nh 0; catch { set nh [sta::endpoint_violation_count min] }
if {$nh > 0} { qb_hold; qb_counts postcts_hold1_unlegal; qb_legal postcts_hold1_legal }
check_placement
