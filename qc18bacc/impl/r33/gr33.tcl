# R33: GRT routing-resource table (GRT-0053) on a db with the production layer adjustments; R33_NOPDN "M7 ..." drops the
# special (PDN) wires of those layers first (in memory); R33_ADJ0 1: no adjustments
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set _f [open $::OUT/config.tcl]; set _t [read $_f]; close $_f
eval [string map {r31_snap/ r31_snap4/} $_t]
qc_config
qc_read_liberty
read_db $::OUT/db/[qc_env R33_DB cts_rt].odb
read_sdc $::OUT/db/[qc_env R33_DB cts_rt].sdc
qc_set_rc
set blk [ord::get_db_block]
set drop [qc_env R33_NOPDN ""]
if {$drop ne ""} {
  set k 0
  foreach net [$blk getNets] { if {![$net isSpecial]} continue
    foreach sw [$net getSWires] { foreach w [$sw getWires] { if {![$w isVia] && [lsearch $drop [[$w getTechLayer] getName]] >= 0} { odb::dbSBox_destroy $w; incr k } } } }
  puts "R33G dropped $k special wires on $drop"
}
set_routing_layers -signal M2-M9 -clock M2-M9
if {![qc_env R33_ADJ0 0]} { set_global_routing_layer_adjustment M2-M9 0.25; foreach {l a} {M5-M9 0.10 M2-M3 0.6} { set_global_routing_layer_adjustment $l $a } }
global_route -congestion_iterations 0 -allow_congestion -verbose
exit
