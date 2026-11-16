# R12 probe: GRT with 0 congestion iterations on QB_DB of QC_PNR_OUT, then try the routing heatmap settings.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set_thread_count 4
read_db $::OUT/db/[qc_env QB_DB grt_pl3].odb
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER 0.25
global_route -congestion_iterations 0 -allow_congestion
puts "R12P haveRoutes [grt::have_routes]"
foreach k {Type Direction Layer GridX} { catch {puts "R12P get $k [gui::get_heatmap_string Routing $k]"} e; puts "R12P e $e" }
catch {gui::set_heatmap Routing rebuild} e; puts "R12P rebuild $e"
catch {gui::dump_heatmap Routing /tmp/ckp908/r12_hm_def.csv} e; puts "R12P dump def $e"
foreach {k v} {Type Capacity Type capacity Type Usage Type Congestion Direction Horizontal Direction horizontal Direction All Layer M3 Layer All} {
  if {[catch {gui::set_heatmap Routing $k $v} e]} { puts "R12P set $k $v ERR $e" } else { puts "R12P set $k $v OK" }
}
gui::set_heatmap Routing Layer M3; catch {gui::set_heatmap Routing Type Capacity}; catch {gui::set_heatmap Routing rebuild}
catch {gui::dump_heatmap Routing /tmp/ckp908/r12_hm_m3cap.csv} e; puts "R12P dump m3cap $e"
exit
