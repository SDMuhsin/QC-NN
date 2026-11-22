# R38 opt-in fix for F4 (results/r38.md): full detailed re-route of a block whose last ECO used the incremental re-route
# (repair/hold_eco.tcl QB35_HDR_FULL 0), keeping its netlist and placement exactly.  Same routing recipe as hold35.tcl's
# QB35_HDR_FULL 1 branch (fillers out, every non-special wire destroyed, old pin access dropped (route/pa_reset.tcl),
# global_route + detailed_route, fillers back, flow finish.tcl; kit min-step / EOL rules route/drc_rules.tcl).  Run in an R38 COPY run dir via common/or.sh <tag> reroute38.tcl <log>; loads db/<QB38_RRDB>.odb.
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QB35_THREADS [qc_env QC_PNR_THREADS 16]]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env QB38_RRDB eco]
# QB38_RR_MIN 1 (disk): drop the loaded copy db after reading, save only finish
if {[qc_env QB38_RR_MIN 0]} { file delete $::OUT/db/[qc_env QB38_RRDB eco].odb }
if {[qc_env QB38_RR_DRY 0]} { puts "R38_RR dry"; exit }
set blk [ord::get_db_block]
set ni [llength [$blk getInsts]]
set nf 0; foreach i [$blk getInsts] { if {[string match FILLER_* [$i getName]]} { odb::dbInst_destroy $i; incr nf } }
set nr 0; foreach n [$blk getNets] { if {[$n isSpecial]} continue; set w [$n getWire]; if {$w ne "NULL"} { odb::dbWire_destroy $w; incr nr } }
puts "R38_RR insts $ni fillers_removed $nf wires_destroyed $nr"
set fill {}
if {[p DCAP]} { set fill [concat $fill $::QC_PNR_DCAP] }
if {[p FILL]} { set fill [concat $fill $::QC_PNR_FILL] }
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
foreach {l a} [qc_env QB15_GADJ_L ""] { set_global_routing_layer_adjustment $l $a }
# fillers / decaps BEFORE detailed_route, as flow pnr/or/route.tcl (hold35.tcl's default places them after DR: DCAP M1 then
# lands next to router VIA12 pads -> Calibre M1.S.1, results/r38.md F8); QB38_RR_FILL_AFTER 1 = hold35 order
if {[llength $fill] && ![qc_env QB38_RR_FILL_AFTER 0]} { filler_placement $fill; check_placement }
source $::QBF/route/pa_reset.tcl
set t [clock seconds]
global_route -guide_file $::OUT/route_rr.guide -allow_congestion -congestion_iterations 10
puts "R38_RR global_route [expr {[clock seconds] - $t}] s"
source $::QBF/route/drc_rules.tcl
set t [clock seconds]
detailed_route -output_drc $::OUT/rpt/drt_rr.drc.rpt -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
    -droute_end_iter [qc_env QB35_HDR_ITER 64] -verbose 1
puts "R38_RR detailed_route [expr {[clock seconds] - $t}] s"
set nv 0; catch { set g [open $::OUT/rpt/drt_rr.drc.rpt]; set nv [regexp -all {violation type} [read $g]]; close $g }
puts "R38_RR drc_violations $nv"
if {![qc_env QB38_RR_MIN 0]} { qc_save route_dr }
if {[llength $fill] && [qc_env QB38_RR_FILL_AFTER 0]} { filler_placement $fill }
if {![qc_env QB38_RR_MIN 0]} { qc_save route }
source $::env(QC_FLOW)/pnr/or/finish.tcl
qc_save finish
puts "R38_RR saved ([expr {[clock seconds] - $::T0}] s)"
exit
