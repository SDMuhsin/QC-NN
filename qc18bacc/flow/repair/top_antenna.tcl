# Antenna repair of the top at GRT (results/r43.md defect 5, r46.md; route/top_post_grt.tcl QB43_GRTANT 1,
# repair/top_hold.tcl): the top flow stops after GRT and runs DR in a fresh process, so route.tcl's repair_antennas never
# ran (r39_v: 89 nets after DR).  Repair against the LEF rule as the sign-off check signoff/antenna.tcl reads it (this OR
# applies the scalar CAR and never the diffusion PWL): scalar CAR of M1-M8 set to 0 in memory for the repair, restored
# after (the db keeps the LEF values).  25 % ratio margin for the GRT -> DRT length change (R40 hub: 3 nets at
# 1.04-1.27x without margin), 3 iterations.
proc q43_ant {} {
    set t [clock seconds]; array set car {}
    foreach ln {M1 M2 M3 M4 M5 M6 M7 M8} {
        set l [[[ord::get_db] getTech] findLayer $ln]
        if {$l eq "NULL" || ![$l hasDefaultAntennaRule]} continue
        set r [$l getDefaultAntennaRule]; set car($ln) [$r getCAR]; $r setCAR 0
    }
    # R46 (results/r46.md; BAND-AID for an OpenROAD bug): the SEGFAULT is not a thread race.  Under
    # 3D overflow FastRoute assigns edges to layers below the min routing layer (M1, capacity 0), and RepairAntennas::
    # addWireTerms, joining such an M1 wire to an M1 pin, adds the M2-M3 default via while the wire encoder is on M1 ->
    # dbWireEncoder writes via id 0 -> null bbox in odb::orderWires.  With the GRT min layer at M1 for the repair only,
    # M1 pins join through the route's own M1-M2 via segments and no via is mis-encoded.  Restored right after.
    set_routing_layers -signal M1-$::QC_PNR_MAX_LAYER -clock M1-$::QC_PNR_MAX_LAYER
    set rc [catch { repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations 3 -ratio_margin 25 } e]
    set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
    foreach ln [array names car] { [[[[ord::get_db] getTech] findLayer $ln] getDefaultAntennaRule] setCAR $car($ln) }
    set nd 0; foreach i [[ord::get_db_block] getInsts] { if {[[$i getMaster] getName] eq [lindex $::QC_PNR_DIODE 0]} { incr nd } }
    qc_summary "r43 grt antenna repair rc $rc diodes $nd [expr {[clock seconds] - $t}] s $e"
}
