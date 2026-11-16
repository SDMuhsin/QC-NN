# QC_HOOK of the R9a qb_act2_blk synthesis (results/r9a.md).  As impl/r7c/topo_act.tcl (IO budget budget.tcl, buffered
# multi-port nets, topographical context) with three changes that remove R7c's DRV-repair bloat at its root:
#   * DRV limits = the P&R limits (QB9_MAXTRAN 0.30 ns, QB9_MAXFO 32) instead of min(0.5, 0.1 P) = 0.165 ns / 16:
#     P&R (impl/r9a/act.cfg) checks the same numbers, so DC's sizing / buffering is what P&R keeps
#   * compile_final_drc_fix all: R8c's DC log shows the DRV fixing pass followed by the -spg re-placement + area
#     recovery, which deleted the fix buffers (design rule cost 77 k -> 205 k) and left 36 900 max-transition nets
#     (e.g. act pipe0 -> pipe1, 1.8 ns) for the P&R repair
#   * topographical die = the P&R die: utilisation QB_UTIL_T (default 0.46) and aspect QB_ASPECT (default 2.7), act pins
#     east, S / map read data + read ports south, controls / tokens / descriptors / flags north (QB9_CTL_SIDE T)
source [file dirname [info script]]/../r7c/budget.tcl
qb7_io_apply [get_attribute [get_clocks qb_clk] period]
set_fix_multiple_port_nets -all -buffer_constants
set_max_transition [qc_env QB9_MAXTRAN 0.30] [current_design]
set_max_fanout [qc_env QB9_MAXFO 32] [current_design]
if {[catch {set_app_var compile_final_drc_fix all} e]} { puts "QB9_TOPO compile_final_drc_fix unavailable: $e" }
if {[shell_is_in_topographical_mode]} {
    set_utilization [qc_env QB_UTIL_T 0.46]
    set_aspect_ratio [qc_env QB_ASPECT 2.7]
    set _a [get_ports {act[*]}]
    set _s [get_ports {s_q[*] m_q[*] s_ren s_ra[*] s_ctx m_ren m_ra[*] m_ctx}]
    set_port_side -side R $_a
    set_port_side -side B $_s
    set _c [remove_from_collection [add_to_collection [all_inputs] [all_outputs]] [add_to_collection $_a $_s]]
    set_port_side -side [qc_env QB9_CTL_SIDE T] $_c
    puts "QB9_TOPO util [qc_env QB_UTIL_T 0.46] aspect [qc_env QB_ASPECT 2.7] maxtran [qc_env QB9_MAXTRAN 0.30] maxfo [qc_env QB9_MAXFO 32] ctl [sizeof_collection $_c]"
}
