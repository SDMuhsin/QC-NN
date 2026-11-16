# R8d DC experiment (QB_DC_XHOOK, sourced at the end of impl/r5b/dc_hook.tcl; no constraint change, no exception): the
# paths into the column-block ETM input pins (core_in: act / pf feedthrough artefacts of the pre-route ETM, DC WNS
# -4.5 ns, results/r8a.md) get their own path group, so that the qb_clk group's worst (and DC's critical-range effort)
# is the top logic instead of the ETM artefact.
set blks [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name==qb_col_blk"]
if {[sizeof_collection $blks]} {
    group_path -name qb_blk_in -to [get_pins -of_objects $blks -filter "direction==in && lib_pin_name!=clk"]
    puts "QB_R8D_GRP qb_blk_in [sizeof_collection [get_pins -of_objects $blks -filter {direction==in}]] pins"
}
