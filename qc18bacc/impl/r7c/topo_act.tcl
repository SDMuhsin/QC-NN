# QC_HOOK of the qb_act2_blk synthesis (results/r7c.md): topographical context of the west-strip hard block
# (utilisation QB_UTIL_T, aspect H / W QB_ASPECT, pin sides: act east, S / map read south, controls + clk west),
# the IO budget (budget.tcl), and buffered multi-port nets.
source [file dirname [info script]]/budget.tcl
qb7_io_apply [get_attribute [get_clocks qb_clk] period]
set_fix_multiple_port_nets -all -buffer_constants
if {[shell_is_in_topographical_mode]} {
    set_utilization [qc_env QB_UTIL_T 0.60]
    set_aspect_ratio [qc_env QB_ASPECT 2.3]
    set_port_side -side R [get_ports {act[*]}]
    set_port_side -side B [get_ports {s_q[*] m_q[*]}]
    set _w [remove_from_collection [all_inputs] [get_ports {act[*] s_q[*] m_q[*]}]]
    set_port_side -side L [add_to_collection $_w [remove_from_collection [all_outputs] [get_ports {act[*]}]]]
    puts "QB7_TOPO util [qc_env QB_UTIL_T 0.60] aspect [qc_env QB_ASPECT 2.3]"
}
