# R36 QB_PC_HOOK for the top (impl/pnr/slice_post_cts.tcl): no post-CTS repair at all (setup is repaired once at GRT
# parasitics by impl/r35/shim/post_grt.tcl; hold is signed off in PrimeTime).  r36_f1: the setup-only hook spent > 40 min
# on 763 endpoints dominated by unfixable chip-IO paths (rst_n recovery, h_go) at placement parasitics.
qb_counts postcts_norepair
check_placement
