# QC_HOOK of the hardened-PE synthesis (results/pnr_pe.md): DC topographical context of the square PE block of
# impl/hard/pe.cfg.  Port sides as the block pins: act a / b2 west (column act pins), BR-driven codes / NNw / ctl /
# T2 and the drain shifts east (spine with decoders + BR), shadow chain in from above (PE r + 4), out below.
# IO delays are the column's (impl/constraints.sdc, 20 % of the period); outputs drive QB_HB_OLOAD pF (default
# 0.05: a ~2-level top wire between blocks, no repeaters over the blocks).
if {[shell_is_in_topographical_mode]} {
    set_utilization [qc_env QB_UTIL_T 0.70]
    set_aspect_ratio 1.0
    set_port_side -side L [get_ports {a[*] b2[*]}]
    set_port_side -side R [get_ports {c[*] nnw[*] ctl[*] t2[*] fsh wsh clk rst_n}]
    set_port_side -side T [get_ports {up[*] sh_in[*]}]
    set_port_side -side B [get_ports {shd[*] sh_out[*]}]
}
set_load [qc_env QB_HB_OLOAD 0.05] [all_outputs]
puts "QB_TOPO_PE util [qc_env QB_UTIL_T 0.70] oload [qc_env QB_HB_OLOAD 0.05]"
