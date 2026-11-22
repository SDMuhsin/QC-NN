# PrimeTime DRV ECO of a routed block at one corner (R48, results/r48.md): OpenROAD repairs max transition / max cap with the
# liberty pin capacitance it reads, PrimeTime signs off with the CCS receiver capacitance range (upper bound up to 2.3 x:
# r48_col NR2XD8 A1 0.012 / 0.028 pF), so routed blocks that OpenROAD sees clean fail the PT DRV check (r48_col tt 1 000 /
# 1 165, ss 22 538 / 2 058 transition / capacitance pins).  Here PrimeTime itself repairs them (fix_eco_drc -methods
# {size_cell insert_buffer}: driver sizing and BUFFD2 / 4 / 8 buffers, legalised and routed by the caller) and writes the
# changes for OpenROAD (<run>/out/drv_eco_<corner>.tcl, size_cell + insert_buffer lines; repair/hold_eco.tcl QB35_ECO_TCL
# applies both, r48_insbuf, before its full re-route).
# The design setup is the block's own sign-off script (QB_PT_SCRIPT) evaluated up to its first update_timing; a
# QB_PT_PRE_ECO file (the changes of an earlier corner) is applied first; write_changes then holds both corners (the
# last corner's file is the cumulative ECO).
set f [open $::env(QB_PT_SCRIPT)]; set t [read $f]; close $f
set k [string first "\nupdate_timing\n" $t]
eval [string range $t 0 $k]
if {[info exists ::env(QB_PT_PRE_ECO)] && [file exists $::env(QB_PT_PRE_ECO)]} { source $::env(QB_PT_PRE_ECO); puts "QB_DRV_ECO applied $::env(QB_PT_PRE_ECO)" }
update_timing
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/signoff/pt/common.tcl]
# the P&R dont_use list (flow/tsmc65 site QC_PNR_DONT_USE): PrimeTime must not pick cells OpenROAD may not use
foreach _p {*D0 DEL* G* LVL* ISO* CKLHQ* OD18*} { set _c [get_lib_cells -quiet */$_p]; if {[sizeof_collection $_c]} { set_dont_use $_c } }
qb_pt_drv stdout
fix_eco_drc -type max_transition -methods {size_cell insert_buffer} -buffer_list {BUFFD2 BUFFD4 BUFFD8} -cell_type {combinational sequential} -verbose
fix_eco_drc -type max_capacitance -methods {size_cell insert_buffer} -buffer_list {BUFFD2 BUFFD4 BUFFD8} -cell_type {combinational sequential} -verbose
qb_pt_drv stdout
write_changes -format icctcl -output $dir/out/drv_eco_$corner.tcl
puts "QB_DRV_ECO done $corner"
exit
