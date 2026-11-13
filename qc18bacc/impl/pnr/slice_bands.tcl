# Band geometry of the column strip (sourced by slice_pins.tcl and slice_place.tcl; results/pnr_slice.md).
# Bottom-up in the core: lane band [y0, y0 + HL) (32 fused + 4 wide lanes, both parameter banks, PPU control
# registers), then PE row r = 0..15 in band [y0 + HL + r HP, + HP).  HL / HP from the netlist cell areas (lane-band
# cells vs one PE), decoders / broadcast registers counted with the PE rows (they are placed there).
proc qb_class {name} {
    if {[regexp {^u_core/g_r_(\d+)__g_c_0__u_pe/} $name -> r]} { return pe$r }
    if {[regexp {^u_core/g_(fq|wq)_\d+__} $name]} { return lane }
    if {[regexp {^u_core/u_pb[fw]/} $name]} { return lane }
    if {[regexp {^u_core/g_col_0__g_grp_(\d+)__u_br/} $name -> g]} { return br$g }
    if {[regexp {^u_core/g_col_0__u_dec/} $name]} { return dec }
    # CREG port registers of the codes / item controls (results/pnr_slice2.md): next to the decoders they feed
    if {[regexp {^u_core/(cdr|ctlr|g_creg_cdr|g_creg_ctlr)_?reg} $name]} { return dec }
    return other
}
proc qb_bands {} {
    set blk [ord::get_db_block]
    set u [[ord::get_db_tech] getDbUnitsPerMicron]
    array set a {lane 0 pe 0 rest 0 dec 0}
    foreach i [$blk getInsts] {
        set m [$i getMaster]
        if {![$m isCore]} { continue }
        set ar [expr {[$m getWidth] * double([$m getHeight]) / $u / $u}]
        set c [qb_class [$i getName]]
        if {$c eq "dec"} { set a(dec) [expr {$a(dec) + $ar}] }
        if {$c eq "lane"} { set a(lane) [expr {$a(lane) + $ar}] } elseif {[string match pe* $c]} { set a(pe) [expr {$a(pe) + $ar}] } else { set a(rest) [expr {$a(rest) + $ar}] }
    }
    set core [$blk getCoreArea]
    set ::QB_X0 [expr {[$core xMin] / double($u)}]; set ::QB_X1 [expr {[$core xMax] / double($u)}]
    set ::QB_Y0 [expr {[$core yMin] / double($u)}]; set ::QB_Y1 [expr {[$core yMax] / double($u)}]
    set H [expr {$::QB_Y1 - $::QB_Y0}]
    set tot [expr {$a(lane) + $a(pe) + $a(rest)}]
    # "other" (top glue: PPU control registers, drain-shift copies) is small; it goes with the lanes
    set ::QB_HL [expr {$H * ($a(lane) + 0.5 * $a(rest)) / $tot}]
    # QB_DEC_TOP 1 (results/pnr_slice3.md): a decoder band of height QB_HD at the top of the strip (decoders + CREG
    # port registers at utilisation QB_DEC_UTIL, default 0.7), where global placement takes them anyway (next to the
    # cd / ctl pins on the top edge); the PE rows share the rest.  Default 0: no decoder band (slice v1 / v2).
    set ::QB_HD [expr {[qb_env QB_DEC_TOP 0] ? $a(dec) / [qb_env QB_DEC_UTIL 0.7] / ($::QB_X1 - $::QB_X0) : 0.0}]
    set ::QB_HP [expr {($H - $::QB_HL - $::QB_HD) / 16.0}]
    qc_log [format "slice bands: lane-band cells %.0f um2, PE cells %.0f um2, other %.0f um2 (decoders %.0f); lane band %.1f um, PE row %.1f um, decoder band %.1f um" \
        $a(lane) $a(pe) $a(rest) $a(dec) $::QB_HL $::QB_HP $::QB_HD]
}
proc qb_row_y {r} { return [list [expr {$::QB_Y0 + $::QB_HL + $r * $::QB_HP}] [expr {$::QB_Y0 + $::QB_HL + ($r + 1) * $::QB_HP}]] }
