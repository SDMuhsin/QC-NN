# R30 A/B probe (no db written): GRT + short DR of a run's pre-route db (R30_DB [cts_rt]) with the flow's settings,
# optional variants:  R30_HOFF <um>  re-make the horizontal-layer tracks with this y offset (default: keep LEF tracks)
#                     R30_IT [1]     -droute_end_iter;  R30_RPT  -output_drc file (with -drc_report_iter_step 1)
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R30_DB cts_rt]
set_thread_count [qc_env R30_THR 8]
# R30_MINL <layer>: bottom routing layer for GRT + DR instead of the kit's QC_PNR_MIN_LAYER
if {[qc_env R30_MINL ""] ne ""} { set ::QC_PNR_MIN_LAYER [qc_env R30_MINL]; puts "R30A bottom layer $::QC_PNR_MIN_LAYER" }
set blk [ord::get_db_block]; set tech [ord::get_db_tech]; set u [$tech getDbUnitsPerMicron]
# R30_PDN <tcl>: sourced after loading (e.g. impl/r29/pdn29.tcl, the R29 macro-PDN strap trim; in memory only)
if {[qc_env R30_PDN ""] ne ""} { source [qc_env R30_PDN] }
if {[qc_env R30_HOFF ""] ne ""} {
  set die [$blk getDieArea]
  foreach tg [$blk getTrackGrids] {
    set l [$tg getTechLayer]
    if {[$l getDirection] ne "HORIZONTAL"} continue
    set p [$l getPitch]; set off [expr {round([qc_env R30_HOFF] * $u)}]
    set ny [expr {([$die yMax] - $off) / $p + 1}]
    set xs [$tg getGridX]
    set nx [llength $xs]; set x0 [lindex $xs 0]
    odb::dbTrackGrid_destroy $tg
    set ng [odb::dbTrackGrid_create $blk $l]
    $ng addGridPatternX $x0 $nx $p
    $ng addGridPatternY $off $ny $p
    puts "R30A tracks [$l getName] y offset [qc_env R30_HOFF] pitch [expr {$p / double($u)}] ny $ny"
  }
}
# R30_NOPGVIA 1: delete every special-net via (PDN stacks) and every special-net wire on R30_NOPG_LAYERS [M2 M3]
# in memory before GRT / DR (non-physical A/B: how much of the DR difficulty the PDN stacks cause)
if {[qc_env R30_NOPGVIA 0]} {
  set nv 0; set nw 0
  foreach net [$blk getNets] {
    if {![$net isSpecial]} continue
    foreach sw [$net getSWires] {
      foreach b [$sw getWires] {
        if {[$b isVia]} { odb::dbSBox_destroy $b; incr nv } elseif {[[$b getTechLayer] getName] in [qc_env R30_NOPG_LAYERS {M2 M3}]} { odb::dbSBox_destroy $b; incr nw }
      }
    }
  }
  puts "R30A removed PG vias $nv wires $nw"
}
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
foreach {l a} [qc_env QB15_GADJ_L ""] { set_global_routing_layer_adjustment $l $a }
foreach {l a} [qc_env R30_GADJ ""] { set_global_routing_layer_adjustment $l $a; puts "R30A gadj $l $a" }
global_route -congestion_iterations [p GR_ITER] -allow_congestion
set t [clock seconds]
set extra {}
if {[qc_env R30_RPT ""] ne ""} { set extra [list -output_drc [qc_env R30_RPT] -drc_report_iter_step 1] }
detailed_route -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
    -droute_end_iter [qc_env R30_IT 1] -verbose 1 {*}$extra
puts "R30A detailed_route [expr {[clock seconds] - $t}] s"
exit
