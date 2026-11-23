# Chip PG strap grid of the standard-cell area (one source for every block and the chip top; plain Tcl, no tool command):
#   ::QB_PG_GRID   {layer dir width pitch offset} per strap layer, VSS / VDD pairs.  Convention (OpenROAD pdngen, which
#                  built the reference column r5b, the act block r48 and the top's core grid): offset = core edge -> low
#                  edge of the first strap, the first strap is VSS (pdngen starts_with GROUND), VDD at + pitch / 2.
#                  With the 5-um core margin of the blocks: M7 VSS y 10.0-10.8, VDD 25.0-25.8, pitch 30 (reference column
#                  abstract, act LEF VDD 1945.0 / VSS 1960.0).
#   ::QB_PG_PIN    the strap layer whose straps are the hard blocks' VDD / VSS pins, across the whole block width (the
#                  top drops its M8 straps on them: floorplan/pdn_macro.tcl, M7 -> M8 vias on the block pins)
#   qb_pg_strap <layer>          {dir width pitch offset} of that layer
#   qb_pg_expect <layer> <net> <lo> <hi>  low edges of that net's straps in a core spanning lo .. hi (across the straps)
# Users: floorplan/pdn_m8.tcl + pe_pdn.tcl (OpenROAD), flow/icc2/floorplan.tcl (ICC2 mesh) and its PG pin gate
# (flow/icc2/common.tcl qb_pg_check, floorplan + abstract).
set ::QB_PG_GRID {{M4 vertical 0.4 20.0 2.0} {M7 horizontal 0.8 30.0 5.0}}
set ::QB_PG_PIN  M7
proc qb_pg_strap {ly} {
    foreach s $::QB_PG_GRID { if {[lindex $s 0] eq $ly} { return [lrange $s 1 end] } }
    error "qb_pg_strap: no $ly in QB_PG_GRID"
}
proc qb_pg_expect {ly net lo hi} {
    lassign [qb_pg_strap $ly] dir w pitch off
    set y [expr {$lo + $off + ($net eq "VDD" ? $pitch / 2.0 : 0.0)}]
    set v {}
    for {} {$y + $w <= $hi + 1e-6} {set y [expr {$y + $pitch}]} { lappend v [format %.3f $y] }
    return $v
}
