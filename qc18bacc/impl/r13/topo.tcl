# QC_HOOK of the R13 qb_act2_blk synthesis (results/r13.md): impl/r9a/topo.tcl + keep the QB_ACT_RPL replicas apart.
# The 16 s1c copies (s1c_r) and the 2 x 128 line-buffer write-enable copies (wer) have identical D logic; compile_ultra's
# register merging (compile_enable_register_merging, default true) would fold each group back into one flop and
# rebuild the 16 k-fanout trees.  set_register_merging false on exactly these flops keeps them; sizing / buffering of
# their fanout stays free (no dont_touch).
source [file dirname [info script]]/../r9a/topo.tcl
set _rpl [get_cells -hierarchical -filter "is_sequential==true" {*s1c_r_reg* *wer_reg*}]
puts "QB13_RPL replica flops [sizeof_collection $_rpl]"
if {[sizeof_collection $_rpl] > 0} { set_register_merging $_rpl false }
