# QC_HOOK of the qb_act2_blk synthesis (synth/run.sh act; results/r9a.md, r13.md, r20.md).  As impl/r7c/topo_act.tcl (IO budget budget.tcl, buffered
# multi-port nets, topographical context) with three changes that remove R7c's DRV-repair bloat at its root:
#   * DRV limits = the P&R limits (QB9_MAXTRAN 0.30 ns, QB9_MAXFO 32) instead of min(0.5, 0.1 P) = 0.165 ns / 16:
#     P&R (the OpenROAD-era act config, removed: flow/README.md) checked the same numbers, so DC's sizing / buffering is what P&R keeps
#   * compile_final_drc_fix all: R8c's DC log shows the DRV fixing pass followed by the -spg re-placement + area
#     recovery, which deleted the fix buffers (design rule cost 77 k -> 205 k) and left 36 900 max-transition nets
#     (e.g. act pipe0 -> pipe1, 1.8 ns) for the P&R repair
#   * topographical die = the P&R die: utilisation QB_UTIL_T (default 0.46) and aspect QB_ASPECT (default 2.7), act pins
#     east, S / map read data + read ports south, controls / tokens / descriptors / flags north (QB9_CTL_SIDE T)
source [file dirname [info script]]/../blocks/act/io_budget.tcl
# knobs (flow/tsmc65/common/knobs.tcl: declared once, recorded by DC in run.env)
qc_knobs_declare {QB9_MAXTRAN 0.30 QB9_MAXFO 32 QB_UTIL_T 0.46 QB_ASPECT 2.7 QB9_CTL_SIDE T}
qb7_io_apply [get_attribute [get_clocks qb_clk] period]
set_fix_multiple_port_nets -all -buffer_constants
set_max_transition [qc_knob QB9_MAXTRAN] [current_design]
set_max_fanout [qc_knob QB9_MAXFO] [current_design]
if {[catch {set_app_var compile_final_drc_fix all} e]} { puts "QB9_TOPO compile_final_drc_fix unavailable: $e" }
if {[shell_is_in_topographical_mode]} {
    set_utilization [qc_knob QB_UTIL_T]
    set_aspect_ratio [qc_knob QB_ASPECT]
    set _a [get_ports {act[*]}]
    set _s [get_ports {s_q[*] m_q[*] s_ren s_ra[*] s_ctx m_ren m_ra[*] m_ctx}]
    set_port_side -side R $_a
    set_port_side -side B $_s
    set _c [remove_from_collection [add_to_collection [all_inputs] [all_outputs]] [add_to_collection $_a $_s]]
    set_port_side -side [qc_knob QB9_CTL_SIDE] $_c
    puts "QB9_TOPO util [qc_knob QB_UTIL_T] aspect [qc_knob QB_ASPECT] maxtran [qc_knob QB9_MAXTRAN] maxfo [qc_knob QB9_MAXFO] ctl [sizeof_collection $_c]"
}
# R13: keep the QB_ACT_RPL replicas apart.  The 16 s1c copies (s1c_r) and the 2 x 128 line-buffer write-enable copies (wer)
# have identical D logic; compile_ultra's register merging would fold each group back into one flop and rebuild the 16 k-fanout
# trees.  set_register_merging false on exactly these flops keeps them; sizing / buffering of their fanout stays free.
set _rpl [get_cells -hierarchical -filter "is_sequential==true" {*s1c_r_reg* *wer_reg*}]
puts "QB13_RPL replica flops [sizeof_collection $_rpl]"
if {[sizeof_collection $_rpl] > 0} { set_register_merging $_rpl false }
# R20: no register merging of the QB_ACT_S1T copies (pre-mux selects s1t_c, band selects selt / sel2t, shift selects shqt).
set _r20 [get_cells -hierarchical -filter "is_sequential==true" {*s1t_c_reg* *selt_reg* *sel2t_reg* *shqt_reg*}]
puts "QB20_RPL replica flops [sizeof_collection $_r20]"
if {[sizeof_collection $_r20] > 0} { set_register_merging $_r20 false }
