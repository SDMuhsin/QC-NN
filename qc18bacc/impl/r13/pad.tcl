# R13 (results/r13.md): DPL cell padding on the S1 AND-OR cells (instances u_act/u_s1/*: AOI22 / AOI211 / ND4, ~45 k
# cells, ~0.12 mm2).  Mechanism (m2_short.py on r9a_f2j): the hottest 10 % of 10-um bins hold 45 % of the 1.03 M
# iteration-0 M2 shorts; there S1 cells are 59 % of the cell area, local utilisation 0.86 and 0.98 signal pins / um2
# (block mean 0.62 util); the AOI22D1 pins are M1 shapes reached through M2, so the M2 demand is the pin density.
# Padding QB13_PAD sites (default 1) left and right of every S1 cell lowers that pin density by ~1.3-1.4x locally.
# set_placement_padding lives in the DPL state (not the odb): sourced before placement and again before the post-CTS
# detailed placement (r13/post_cts.tcl).
set _pad [qb_env QB13_PAD 1]
if {$_pad > 0} {
    set _s1 [get_cells -hierarchical u_act/u_s1/*]
    set_placement_padding -instances $_s1 -left $_pad -right $_pad
    qc_log "r13 padding $_pad sites left / right on [llength $_s1] S1 cells"
}
