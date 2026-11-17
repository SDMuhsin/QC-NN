# QC_HOOK of the R20 qb_act2_blk synthesis (results/r20.md): impl/r13/topo.tcl (r9a hook + no merging of the R13 replicas)
# + no register merging of the R20 QB_ACT_S1T copies (pre-mux selects s1t_c, band selects selt / sel2t, shift selects shqt).
source [file dirname [info script]]/../r13/topo.tcl
set _r20 [get_cells -hierarchical -filter "is_sequential==true" {*s1t_c_reg* *selt_reg* *sel2t_reg* *shqt_reg*}]
puts "QB20_RPL replica flops [sizeof_collection $_r20]"
if {[sizeof_collection $_r20] > 0} { set_register_merging $_r20 false }
