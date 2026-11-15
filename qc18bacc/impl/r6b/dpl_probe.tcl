# impl/r6b: detailed-placement probe on db/predpl.odb (place.tcl QB_STOP_DPL 1): QB_SNAP 0 / 1 / 2 (place.tcl qb6_snap)
# then detailed_placement with QB_DPL_ARGS; prints the wall time.  Nothing is written back.
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/predpl.odb
set _snap [qb_env QB_SNAP 0]
set ::env(QB_SPREAD_P) [qb_env QB_SPREAD 0]; set ::env(QB_SPREAD) 0
set ::env(QB_SNAP) 0; set ::env(QB_MAXTRAN) ""; set ::env(QB_STOP_DPL) 0
source $::QB_R6B/place.tcl
set ::env(QB_SNAP) $_snap
set t [clock seconds]
if {$_snap} { qb6_snap }
if {[qb_env QB_SPREAD_P 0]} {
    # probe: every non-buffer cell counts as staying (the predpl db has no legal-group record)
    foreach i [[ord::get_db_block] getInsts] {
        if {[[$i getMaster] isBlock] || [regexp {^(wire|fanout|max_length|load_slew|max_cap|split|rebuffer)} [$i getName]]} continue
        set ::QB6_M($i) [[$i getMaster] getName]
    }
    set t2 [clock seconds]; if {[qb_env QB_SPREAD_P 0] == 2} { qb6_spread2 } else { qb6_spread }; puts "DPL_PROBE spread_s [expr {[clock seconds] - $t2}]"
}
if {[qb_env QB_DPL_FIRM 0]} {
    # probe of place.tcl QB_DPL_FIRM: cells whose origin is on a row site grid and not a repair buffer are FIRM
    set nf 0
    foreach i [[ord::get_db_block] getInsts] {
        if {[[$i getMaster] isBlock] || [regexp {^(wire|fanout|max_length|load_slew|max_cap|split|rebuffer)} [$i getName]]} continue
        $i setPlacementStatus FIRM; incr nf
    }
    puts "DPL_PROBE firm $nf"
}
set t1 [clock seconds]
detailed_placement {*}[qb_env QB_DPL_ARGS {-max_displacement {1000 1000}}]
puts [format "DPL_PROBE snap %s snap_s %d dpl_s %d" $_snap [expr {$t1 - $t}] [expr {[clock seconds] - $t1}]]
exit
