# PDN_TCL of impl/hard/col.cfg: M1 rails + M4 straps + M7 straps in the standard-cell area (the flow default), plus
# M8 vertical straps over everything (also over the PE blocks, whose M7 straps are their VDD / VSS pins).  M8 width
# 3.0: with 0.4-1.6 um M8 this build generates no M7-M8 via at all (PDN-0110 at every crossing; 0.8-um M7 fixed).
define_pdn_grid -name core
add_pdn_stripe -grid core -layer M1 -width 0.33 -followpins
add_pdn_stripe -grid core -layer M4 -width 0.4 -pitch 20.0 -offset 2.0
add_pdn_stripe -grid core -layer M7 -width 0.8 -pitch 30.0 -offset 5.0
add_pdn_stripe -grid core -layer M8 -width [qb_env QB_M8W 3.0] -pitch 40.0 -offset 10.0
add_pdn_connect -grid core -layers {M1 M4}
add_pdn_connect -grid core -layers {M4 M7}
add_pdn_connect -grid core -layers {M7 M8} {*}[qb_env QB_V78 {}]
