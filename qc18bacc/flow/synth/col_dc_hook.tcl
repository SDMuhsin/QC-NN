# QC_HOOK of the qb_col_blk synthesis (results/r5a.md): topographical context of the hard-block strip (utilisation,
# aspect, pin sides of floorplan/col_pins.tcl), the IO budget (budget.tcl) and a buffered act -> act_o feedthrough.
# The budget at the DC clock (ideal: clock arrivals Ll = Le = 0, as ICC2 init) with the min input delay of the DC corner's
# library clock -> Q x the early OCV derate (qb5_hold_min: common/derate.tcl, common/lib_cells.tcl qb_lib_tcq).  R100 [M]
# hunt on a06c97: the call had kept its pre-R77 one-argument form, so this hook stopped on "wrong # args".
set _h [file dirname [file normalize [info script]]]
source $_h/../common/derate.tcl
source $_h/../common/lib_cells.tcl
source $_h/../blocks/col/io_budget.tcl
qb5_io_apply [get_attribute [get_clocks qb_clk] period] 0.0 0.0 [qb_lib_tcq $::env(QC_CORNER)]
set_fix_multiple_port_nets -all -buffer_constants
if {[shell_is_in_topographical_mode]} {
    set_utilization [qc_env QB_UTIL_T 0.70]
    set_aspect_ratio [qc_env QB_ASPECT 8.8]
    set_port_side -side L [get_ports {act[*]}]
    set_port_side -side R [get_ports {act_o[*]}]
    set_port_side -side T [get_ports {cd* ctl* t2* clk rst_n}]
    set_port_side -side B [get_ports {pf* pw* p_ld w_ld s_rd* w_r* f_vld f_src f_sh w_vld w_sh f_y* f_b* w_y* w_b* f_vld_o w_vld_o b2[*] b2_vld}]
    puts "QB5_TOPO util [qc_env QB_UTIL_T 0.70] aspect [qc_env QB_ASPECT 8.8]"
}
