# QC_HOOK of the hardened-PE column synthesis (results/pnr_pe.md): qb_col_cwfp elaborated as usual, then its 16 PEs
# (qbc_pe #(36, 20, 1, 1)) are re-linked to the compiled block qb_pe_hb (QB_HB_DDC, the DC topographical netlist that
# impl/hard/pe.cfg routes), dont_touch, no boundary optimisation, so the column netlist keeps the block ports exactly
# and only the decoders, BR, lanes and glue are compiled.  Topographical context: the 2-wide column of col.cfg
# (QB_ASPECT, act / b2 of even rows west, odd rows east).
set pes [get_cells -hierarchical -filter "ref_name=~qbc_pe_KB36*"]
puts "QB_HB: [sizeof_collection $pes] PE cells, ref [lsort -unique [get_attribute $pes ref_name]]"
set old [lsort -unique [get_attribute $pes ref_name]]
set names [get_object_name $pes]
# the PE design and its sub-designs (they reappear inside the block ddc)
foreach d $old { remove_design -hierarchy $d }
read_ddc [qc_env QB_HB_DDC]
current_design $::env(QC_TOP)
foreach n $names { change_link [get_cells $n] qb_pe_hb }
link
set pes [get_cells -hierarchical -filter "ref_name==qb_pe_hb"]
set_dont_touch $pes true
set_boundary_optimization $pes false
set_dont_touch [get_designs qb_pe_hb] true
puts "QB_HB: [sizeof_collection $pes] cells linked to qb_pe_hb (dont_touch)"
if {[shell_is_in_topographical_mode]} {
    set_utilization [qc_env QB_UTIL_T 0.66]
    set_aspect_ratio [qc_env QB_ASPECT 5.0]
    set ev {}; set od {}
    for {set r 0} {$r < 16} {incr r} {
        set l [expr {$r % 2 ? "od" : "ev"}]
        for {set b [expr {288 * $r}]} {$b < 288 * ($r + 1)} {incr b} { lappend $l "act\[$b\]" }
        for {set b [expr {8 * $r}]} {$b < 8 * ($r + 1)} {incr b} { lappend $l "b2\[$b\]" }
    }
    set_port_side -side L [get_ports $ev]
    set_port_side -side R [get_ports $od]
    set_port_side -side T [get_ports {cd* ctl* t2* clk rst_n b2_vld}]
    set_port_side -side B [get_ports {pf* pw* s_rd* w_r* f_y* f_b* w_y* w_b* f_vld f_src f_sh p_ld w_vld w_sh w_ld f_vld_o w_vld_o}]
}
