# PDN_TCL of impl/hard/pe.cfg: M1 followpin rails, M4 vertical straps, M7 horizontal straps extended to the block
# boundary and promoted to VDD / VSS block pins (the column drops M8 straps on them, impl/hard/col_pdn.tcl).
define_pdn_grid -name core -pins {M7}
add_pdn_stripe -grid core -layer M1 -width 0.33 -followpins
add_pdn_stripe -grid core -layer M4 -width 0.4 -pitch 20.0 -offset 2.0
add_pdn_stripe -grid core -layer M7 -width 0.8 -pitch 30.0 -offset 5.0 -extend_to_boundary
add_pdn_connect -grid core -layers {M1 M4}
add_pdn_connect -grid core -layers {M4 M7}
