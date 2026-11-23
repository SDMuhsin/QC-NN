# PDN_TCL of impl/hard/pe.cfg: M1 followpin rails, M4 vertical straps, M7 horizontal straps extended to the block
# boundary and promoted to VDD / VSS block pins (the column drops M8 straps on them, floorplan/pdn_m8.tcl).
define_pdn_grid -name core -pins {M7}
add_pdn_stripe -grid core -layer M1 -width 0.33 -followpins
# M4 / M7 straps of the chip PG grid (floorplan/pg_grid.tcl), the M7 ones extended to the block boundary
source [file dirname [info script]]/pg_grid.tcl
foreach _s $::QB_PG_GRID {
    lassign $_s _l _d _w _p _o
    add_pdn_stripe -grid core -layer $_l -width $_w -pitch $_p -offset $_o {*}[expr {$_l eq $::QB_PG_PIN ? "-extend_to_boundary" : ""}]
}
add_pdn_connect -grid core -layers {M1 M4}
add_pdn_connect -grid core -layers {M4 M7}
