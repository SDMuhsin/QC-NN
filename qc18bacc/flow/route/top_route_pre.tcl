# PRE_ROUTE_TCL of blocks/top/top.cfg (results/r14.md, r36.md, r43.md):
#   1. clock balancing at placement parasitics (cts/top_balance.tcl, 2 passes; rpt/clk14.txt)
#   2. chip IO latency L = measured top-flop clock median after balancing (repair/top_io_latency.tcl)
#   3. route/postcts_grt.tcl: post-CTS step of repair/post_cts.tcl with the hook repair/post_cts_none.tcl (no repair:
#      setup / hold are repaired at GRT parasitics, route/top_post_grt.tcl), then GRT with -allow_congestion
source $::QBF/cts/top_balance.tcl
catch { file delete $::OUT/rpt/clk14.txt }
q14_balance 2 placement pl
check_placement
source $::QBF/repair/top_io_latency.tcl; q43_autol post_cts
source $::QBF/route/postcts_grt.tcl
