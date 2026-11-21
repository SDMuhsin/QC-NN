# R43 mini test of the qb_w EMA[1] DR marker (results/r43.md, defect 3): one qb_w_204x144m2 (MX, same track phase as in
# the top) + one TIEL per EMA bit, routed alone.  Run in an empty dir with the run env (QC_FLOW, QC_KIT):
#   openroad -exit ema43.tcl   env R43_EMA_V <variant>: base | tie1 (one TIEL for all three bits) | dx (macro +0.1 um x)
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT [pwd]
set ::P(MACRO_LEFS) [list $::env(R43_WLEF)]
foreach c $::QC_CORNERS { set ::P(MACRO_LIBS_$c) {} }
read_lef [qc_router_lef]
read_lef [qc_macro_lef $::env(R43_WLEF)]
foreach c {tt} { read_liberty [qc_lib_file $c] }
set v [qc_env R43_EMA_V base]
if {$v eq "all"} {
    exec $::env(QC_PY) -I $::env(QC_FLOW)/../../qc18bacc/impl/r43/emaall43.py $::env(R43_WLEF) ema43.v
} else {
set f [open ema43.v w]
if {$v eq "tie1"} {
    puts $f "module t(); wire n0; TIEL t0(.ZN(n0)); qb_w_204x144m2 m(.EMA({n0,n0,n0})); endmodule"
} else {
    puts $f "module t(); wire n0,n1,n2; TIEL t0(.ZN(n0)); TIEL t1(.ZN(n1)); TIEL t2(.ZN(n2)); qb_w_204x144m2 m(.EMA({n2,n1,n0})); endmodule"
}
close $f
}
read_verilog ema43.v; link_design t
initialize_floorplan -site $::QC_PNR_SITE -die_area {0 0 640 300} -core_area {0 0 640 300}
make_tracks
set b [ord::get_db_block]; set u [$b getDefUnits]
set m [$b findInst m]
set dx [expr {$v eq "dx" ? 0.1 : 0.0}]
$m setOrient MX; $m setLocation [expr {int(round((131.6 + $dx) * $u))}] [expr {int(round(97.6 * $u))}]; $m setPlacementStatus FIRM
cut_rows -halo_width_x 7 -halo_width_y 7
# R43_PDN 1: the top's PDN (impl/r5b/pdn.tcl core grid + impl/r5b/pdn_macro.tcl rf macro grid)
if {[qc_env R43_PDN 0]} {
    proc qb_env {n d} { return [expr {[info exists ::env($n)] ? $::env($n) : $d}] }
    set ::P(TOP) t; set ::P(NETLIST) ema43.v; set ::P(SDC) none; qc_config
    set ::P(PDN_TCL) $::env(QC_FLOW)/../../qc18bacc/impl/r5b/pdn.tcl; set ::P(MACRO_PDN_TCL) $::env(QC_FLOW)/../../qc18bacc/impl/r5b/pdn_macro.tcl
    set ::P(MACRO_HALO) {7 7}
    catch { source $::env(QC_FLOW)/pnr/or/pdn.tcl } e; puts "R43_PDN $e"
    proc qc_summary {l} { puts "R43_SUM $l" }
}
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
global_placement -density 0.3 -skip_io
detailed_placement
foreach i [$b getInsts] { set l [$i getLocation]; puts "R43_LOC [$i getName] [expr {[lindex $l 0] / double($u)}] [expr {[lindex $l 1] / double($u)}]" }
global_route
detailed_route -output_drc ema43_[set v].drc -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER {*}[qc_env R43_DRARGS ""]
set n 0; if {[file exists ema43_$v.drc]} { set fh [open ema43_$v.drc]; set n [regexp -all {violation type} [read $fh]]; close $fh }
puts "R43_EMA variant $v markers $n"
