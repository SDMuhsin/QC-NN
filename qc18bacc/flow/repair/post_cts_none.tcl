# QB_PC_HOOK of the top for repair/post_cts.tcl (results/r36.md): no post-CTS repair at all (setup / hold are repaired at
# GRT parasitics by route/top_post_grt.tcl and repair/top_hold.tcl).  r36_f1: the setup-only hook spent > 40 min
# on 763 endpoints dominated by unfixable chip-IO paths (rst_n recovery, h_go) at placement parasitics.
qb_counts postcts_norepair
check_placement
