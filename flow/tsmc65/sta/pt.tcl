# PrimeTime timing of one netlist at one corner (driven by sta/run_pt.sh).
set t0 [clock seconds]
source $::env(QC_FLOW)/common/lib.tcl
set top    $::env(QC_TOP)
set corner $::env(QC_CORNER)
set out    $::env(QC_OUT)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs $corner]]
read_verilog $out/$top.v
current_design $top
link_design
qc_apply_constraints $corner
set par none
if {[file exists $out/$top.spef] && ![catch {read_parasitics -format spef $out/$top.spef}]} { set par dc_topo_estimate }
update_timing
file mkdir $out/rpt
report_timing -max_paths 10 -nosplit                 > $out/rpt/pt_${corner}_max.rpt
report_timing -delay_type min -max_paths 10 -nosplit > $out/rpt/pt_${corner}_min.rpt
report_constraint -all_violators -nosplit            > $out/rpt/pt_${corner}_violators.rpt
check_timing -verbose                                > $out/rpt/pt_${corner}_check.rpt
set fh [open $out/pt_$corner.txt w]
puts $fh "design $top corner $corner lib $::QC_LIB($corner) period_ns $::env(QC_PERIOD) parasitics $par"
qc_put_timing $fh
set hook [qc_env QC_PT_HOOK]
if {$hook ne ""} { source $hook }
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
