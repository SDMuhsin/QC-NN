# R29 opt-in sign-off variant of check_antennas.  This OpenROAD build (2.0-12381, ant checkWireCar) uses the scalar
# ANTENNACUMAREARATIO whenever it is non-zero and then never reads ANTENNACUMDIFFAREARATIO, so diffusion (driver
# outputs, diodes) is never credited.  The TSMC LEF gives both (5000 without diffusion, PWL 5000 / 43027 at
# diff >= 0.06 um2).  Here the scalar CAR of every routing layer that also has a diff-CAR PWL is set to 0 in memory
# (db not written), so the checker applies the PWL with the wire root's own diffusion area: the LEF rule as written.
#   In a run dir (impl/r29/or29.sh <tag> antd29.tcl <log>): R29_DB [route_dr]; rpt/r29_antd_<R29_TAG>.rpt;
#   R29_GRT 1: global_route first (estimate on the GR wires of a grt db).  R29_NETS: verbose nets.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env R29_DB route_dr].odb
set_thread_count 16
if {[qc_env R29_GRT 0]} {
    set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
    set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER 0.25
    foreach {l a} [qc_env QB15_GADJ_L ""] { set_global_routing_layer_adjustment $l $a }
    global_route -congestion_iterations 10 -allow_congestion
}
set tag [qc_env R29_TAG x]
check_antennas -report_file $::OUT/rpt/r29_ant_lit_$tag.rpt
# M1-M8 carry ANTENNACUMAREARATIO 5000 + ANTENNACUMDIFFAREARATIO PWL in tcbn65gplus_9lmT2.lef (M9 has no cum-diff PWL)
foreach ln {M1 M2 M3 M4 M5 M6 M7 M8} {
    set l [[[ord::get_db] getTech] findLayer $ln]
    if {![$l hasDefaultAntennaRule]} continue
    set r [$l getDefaultAntennaRule]
    puts "R29_ANTD $ln scalar CAR [$r getCAR] -> 0"; $r setCAR 0
}
foreach n [qc_env R29_NETS ""] { check_antennas -verbose -net $n }
check_antennas -report_file $::OUT/rpt/r29_antd_$tag.rpt
puts "R29_ANTD done"
exit
