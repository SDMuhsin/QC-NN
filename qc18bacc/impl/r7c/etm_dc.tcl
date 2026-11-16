# Pre-route ETM of qb_act2_blk at one corner (results/r7c.md, stand-in until a routed run exists): DC netlist + DC
# topographical SPEF, ideal clock with latency QB7_ETM_LAT (default 0.55 ns), extract_model -library_cell
# -> $QC_BUILD/r7c_blk/qb_act2_blk_pre_<c>.lib/.db  (as impl/r5a/etm.tcl, which needs the routed netlist + SPEF)
source $::env(QC_FLOW)/common/lib.tcl
set corner $::env(QC_CORNER); set syn $::env(QB7_SYN_DIR); set top qb_act2_blk; set out $::env(QB7_OUT)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner]]
read_verilog $syn/$top.v
current_design $top
link_design
qc_apply_constraints $corner
set_clock_latency [expr {[info exists ::env(QB7_ETM_LAT)] ? $::env(QB7_ETM_LAT) : 0.55}] [get_clocks qb_clk]
read_parasitics -format spef $syn/$top.spef
update_timing
extract_model -library_cell -output $out/${top}_pre_$corner -format {lib db}
puts "QB7_ETM_DONE $corner"
exit
