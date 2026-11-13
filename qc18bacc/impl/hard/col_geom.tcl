# Geometry of the hardened-PE column (col.cfg, results/pnr_pe.md); all um.  Block side from the block LEF SIZE.
#   QB_HL lane-band height, QB_SPINE spine width, QB_HALO block keep-out, QB_LVL_GAP extra gap between PE levels.
set _b 203.8
if {[qb_env QB_HB_LEF {}] ne ""} {
    set _f [open [qb_env QB_HB_LEF {}]]; regexp {SIZE\s+([0-9.]+)\s+BY\s+([0-9.]+)} [read $_f] -> _b _bh; close $_f
}
set ::QB_B   $_b
set ::QB_HL  [qb_env QB_HL 830.0]
set ::QB_S   [qb_env QB_SPINE 56.0]
set _m 5.0; set _h $::QB_HALO; set _g [qb_env QB_LVL_GAP 0.0]
set ::QB_XL [expr {$_m + $_h}]                                  ;# west PE x
set ::QB_XS [expr {$_m + 2 * $_h + $_b}]                        ;# spine x0
set ::QB_XR [expr {$::QB_XS + $::QB_S + $_h}]                   ;# east PE x
set _x1 [expr {$::QB_XR + $_b + $_h}]
set ::QB_YP [expr {$_m + $::QB_HL}]                             ;# bottom of the PE stack
set ::QB_LP [expr {$_b + 2 * $_h + $_g}]                        ;# level pitch
set _y1 [expr {$::QB_YP + 8 * $::QB_LP}]
set ::QB_DIE  [list 0 0 [expr {$_x1 + $_m}] [expr {$_y1 + $_m}]]
set ::QB_CORE [list $_m $_m $_x1 $_y1]
proc qb_lvl_y {L} { return [expr {$::QB_YP + $L * $::QB_LP + $::QB_HALO + [qb_env QB_LVL_GAP 0.0] / 2.0}] }
set ::QB_MPLACE {}
for {set r 0} {$r < 16} {incr r} {
    set L [expr {$r / 2}]
    lappend ::QB_MPLACE [list u_core/g_r_${r}__g_c_0__u_pe [expr {$r % 2 ? $::QB_XR : $::QB_XL}] [qb_lvl_y $L] [expr {$r % 2 ? "MY" : "R0"}]]
}
puts [format "QB_COL_GEOM block %.1f halo %.1f spine %.1f lane band %.1f die %.1f x %.1f" $_b $_h $::QB_S $::QB_HL \
    [lindex $::QB_DIE 2] [lindex $::QB_DIE 3]]
