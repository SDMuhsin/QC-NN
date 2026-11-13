# QC_HOOK of the column-slice synthesis (results/pnr_slice.md): in DC topographical mode, the physical context of
# the OpenROAD strip (impl/pnr/slice.cfg): core utilisation, strip aspect H / W (env QB_ASPECT) and the IO sides of
# impl/pnr/slice_fp.tcl (act / b2 left, codes / controls top, lane stream + parameter banks + PPU controls bottom).
# Wire-load runs ignore it.
if {[shell_is_in_topographical_mode]} {
    set_utilization [qc_env QB_UTIL_T 0.70]
    set_aspect_ratio [qc_env QB_ASPECT 8.8]
    set_port_side -side L [get_ports {act* b2[*]}]
    set_port_side -side T [get_ports {cd* ctl* t2* clk rst_n b2_vld}]
    set_port_side -side B [get_ports {pf* pw* s_rd* w_r* f_y* f_b* w_y* w_b* f_vld f_src f_sh p_ld w_vld w_sh w_ld f_vld_o w_vld_o}]
    puts "QB_TOPO_STRIP util [qc_env QB_UTIL_T 0.70] aspect [qc_env QB_ASPECT 8.8]"
}
