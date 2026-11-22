# PDN_TCL of blocks/top/top.cfg: as floorplan/pdn_m8.tcl (M1 rails, M4 / M7 straps in the standard-cell area, M8
# vertical straps 3.0 um over everything: the column blocks' M7 straps are their VDD / VSS pins), plus M9 horizontal
# straps (chip-level mesh over the 3.1-mm columns; QB_M9 0 drops them).
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/floorplan/pdn_m8.tcl]
if {[qb_env QB_M9 1]} {
    add_pdn_stripe -grid core -layer M9 -width 3.0 -pitch 120.0 -offset 60.0
    add_pdn_connect -grid core -layers {M8 M9}
}
