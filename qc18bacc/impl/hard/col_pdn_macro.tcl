# MACRO_PDN_TCL of impl/hard/col.cfg: the PE blocks' M7 VDD / VSS pins to the column's M8 straps.
define_pdn_grid -macro -default -name macro -halo [p MACRO_HALO] -grid_over_boundary
add_pdn_connect -grid macro -layers {M7 M8} {*}[qb_env QB_V78 {}]
