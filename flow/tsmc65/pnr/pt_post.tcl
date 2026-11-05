# PrimeTime post-route timing of an OpenROAD result at one corner (driven by pnr/run_pt_post.sh):
# routed flat netlist + def2spef.py SPEF of the corner + synthesis SDC with propagated clocks.
set t0 [clock seconds]
source $::env(QC_FLOW)/common/lib.tcl
set top    $::env(QC_TOP)
set corner $::env(QC_CORNER)
set dir    $::env(QC_PNR_OUT)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs $corner]]
set_app_var read_parasitics_load_locations true
read_verilog $dir/out/$top.v
current_design $top
link_design
# constraints as in sta/pt.tcl (regenerated for this corner's library, or QC_SDC) when the synthesis run.env is
# known, else the SDC written by DC (its driving cells / operating conditions name the synthesis corner)
if {[qc_env QC_PERIOD] ne ""} {
    qc_apply_constraints $corner; set sdc_src [expr {[qc_env QC_SDC] ne "" ? "QC_SDC" : "generated"}]
} else {
    read_sdc $::env(QC_SDC_FILE); set sdc_src dc_sdc
}
set_propagated_clock [all_clocks]
read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef
update_timing
file mkdir $dir/rpt
report_annotated_parasitics -list_not_annotated -max_nets 20 > $dir/rpt/pt_post_${corner}_annotation.rpt
report_timing -max_paths 10 -nosplit                 > $dir/rpt/pt_post_${corner}_max.rpt
report_timing -delay_type min -max_paths 10 -nosplit > $dir/rpt/pt_post_${corner}_min.rpt
report_constraint -all_violators -nosplit            > $dir/rpt/pt_post_${corner}_violators.rpt
set fh [open $dir/pt_post_$corner.txt w]
redirect -variable ann { report_annotated_parasitics }
set nets NA
if {[regexp {\n\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|} $ann -> tot rc na]} {
    set nets "total $tot rc_network $rc not_annotated $na"
}
puts $fh "design $top corner $corner lib $::QC_LIB($corner) constraints $sdc_src spef_nets $nets"
qc_put_timing $fh
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
