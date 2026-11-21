# R35 QB_PC_HOOK for the top (impl/pnr/slice_post_cts.tcl): setup repair + legalisation only.  No hold repair at P&R:
# the hub / act block views carry hold / removal arcs of up to 25 ns (ETM extrapolation artefacts at the top's pin
# slews, results/r35.md), which a hold repair would "fix" with long buffer chains; hold is signed off in PrimeTime.
qb_setup
qb_counts postcts_setup_repair
qb_legal postcts_setup_legal
check_placement
