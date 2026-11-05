# DC settings of qc_snitch_cluster_top (QC_HOOK of flow/tsmc65/syn/run_dc.sh: sourced after link and constraints,
# before compile).
#   QC_ELAB_ONLY=1   stop after elaboration / link checks (writes rpt/elab_*.rpt), no compile
set mcs [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~qc_*"]
puts "QC_MACROS [sizeof_collection $mcs] instances of [lsort -unique [get_attribute -quiet $mcs ref_name]]"
# the macros are hard cells: keep them as instantiated
if {[sizeof_collection $mcs]} { set_dont_touch $mcs }
# the clock cells of the tc_clk overlay (ICG / clock mux ...) stay as instantiated (they may still be sized)
set ckc [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~CK*"]
puts "QC_CLOCK_CELLS [sizeof_collection $ckc]"
# fpnew is configured with PipeConfig BEFORE (all FPU pipeline registers at the unit inputs, sim/cfg/chimera_fp.hjson):
# the registers are meant to be retimed into the datapath.  Pipeline retiming of the FPU designs only
# (QC_RETIME = glob of design names, default fpnew_*; empty = off).
set rt [get_designs -quiet [qc_env QC_RETIME fpnew_*]]
if {[sizeof_collection $rt]} {
    set_optimize_registers true -designs $rt
    puts "QC_RETIME [sizeof_collection $rt] designs: [lsort -unique [regsub -all {_[0-9a-f_]+\M} [get_object_name $rt] {}]]"
}
if {[qc_env QC_ELAB_ONLY 0]} {
    redirect $::env(QC_OUT)/rpt/elab_area.rpt  { report_area -nosplit }
    redirect $::env(QC_OUT)/rpt/elab_check_timing.rpt { check_timing }
    redirect $::env(QC_OUT)/rpt/elab_clocks.rpt { report_clocks -nosplit }
    puts "QC_ELAB_ONLY done"
    exit
}
