# Outward planar access for small macro pins (R50, results/r50.md sec. 3).  Opt-in (QB50_MPA, hub).
# The SRAM data pins (e.g. qb_p_240x144m2 Q / D) are 0.16 x 0.16 um M1-M3 squares at the edge of the macro's core OBS.
# Two ways to reach them break the kit min-step rule (M3 MINSTEP 0.09 MAXEDGES 1, Calibre G.4; route/drc_rules.tcl):
#   * a via on the pin: every via enclosure is 0.10 x 0.18 um, it cannot sit on a 0.16 square without a jog;
#   * FlexPA's planar access along the pin row: a macro-pin access point lies on a track inside the pin narrowed by half
#     a wire width (FlexPA_prep.cpp prepPoint_pin_genPoints_rect); when no track falls in that 0.06 um window it takes a
#     point near the pin edge with EAST / WEST access, and the wire that leaves sideways and turns leaves a 0.005-0.04 um
#     notch at the pin edge (DRT Min Step + notch Metal Spacing; the markers DR never cleans).
# A 0.10 um wire that leaves the pin at its centre, straight out of the macro, is clean (one short edge per side).
# qb_macro_pin_ap rewrites the stored access points of every small signal pin of a CLASS BLOCK master: point = pin
# centre, planar access only toward the instance edge nearest to the pin (out of the macro), no via access; an access
# point on a layer below $::QC_PNR_MIN_LAYER moves to that layer when the pin has a shape there.  NearbyGrid points (off
# the pin, they carry an access path segment the Tcl API cannot clear or read; dbAccessType is opaque in Tcl, so a
# point outside the pin is taken as one) lose all access.  Points are relative to the
# instance origin per pin-access class (master + orientation + track offset); the instance is found by the point.
# (dbAccessPoint::create is not callable from Tcl in 2.0-12381: SWIG overload check fails on its uint argument, so the
# existing points are edited.)  The pin shapes, the LEF and the router rules are unchanged.  Use after the last
# placement change:
#   pin_access -bottom_routing_layer .. -top_routing_layer ..;  qb_macro_pin_ap;  detailed_route .. -no_pin_access
# (detailed_route then reads every access point from the db instead of re-running pin access; io::Parser::
# setAccessPoints).  Small = pin bbox below QB50_MPA_MAX um [0.2] in both directions.
proc qb_macro_pin_ap {} {
    set blk [ord::get_db_block]; set u [$blk getDbUnitsPerMicron]
    set smax [expr {round([qb_env QB50_MPA_MAX 0.2] * $u)}]; set tol [expr {round(0.2 * $u)}]
    set lminl [[ord::get_db_tech] findLayer $::QC_PNR_MIN_LAYER]; set lmin [$lminl getRoutingLevel]
    foreach i [$blk getInsts] { if {[string match BLOCK* [[$i getMaster] getType]]} { lappend ins([[$i getMaster] getName]) $i } }
    set nap 0; set ndis 0; set nlay 0; array set ndir {}; array set pins {}
    foreach ap [$blk getAccessPoints] {
        set mp [$ap getMPin]; if {$mp eq "NULL"} continue
        set mt [$mp getMTerm]; set mn [[$mt getMaster] getName]
        if {![info exists ins($mn)] || [$mt getSigType] ne "SIGNAL"} continue
        lassign [$ap getPoint] px py
        set hit ""
        foreach i $ins($mn) {
            set bb [[$i findITerm [$mt getName]] getBBox]; lassign [$i getLocation] lx ly
            set x0 [expr {[$bb xMin] - $lx}]; set y0 [expr {[$bb yMin] - $ly}]; set x1 [expr {[$bb xMax] - $lx}]; set y1 [expr {[$bb yMax] - $ly}]
            if {$px >= $x0 - $tol && $px <= $x1 + $tol && $py >= $y0 - $tol && $py <= $y1 + $tol} { set hit [list $i $bb $x0 $y0 $x1 $y1]; break }
        }
        if {$hit eq ""} continue
        lassign $hit i bb x0 y0 x1 y1
        if {$x1 - $x0 >= $smax || $y1 - $y0 >= $smax} continue
        set pins($mn/[$mt getName]) 1
        if {$px < $x0 || $px > $x1 || $py < $y0 || $py > $y1} {
            foreach d {NORTH SOUTH EAST WEST UP DOWN} { $ap setAccess 0 $d }; incr ndis; continue
        }
        set ib [$i getBBox]; set cx [expr {([$bb xMin] + [$bb xMax]) / 2}]; set cy [expr {([$bb yMin] + [$bb yMax]) / 2}]
        set dir [lindex [lsort -integer -index 1 [list [list NORTH [expr {[$ib yMax] - $cy}]] [list SOUTH [expr {$cy - [$ib yMin]}]] \
            [list EAST [expr {[$ib xMax] - $cx}]] [list WEST [expr {$cx - [$ib xMin]}]]]] 0 0]
        $ap setPoint [odb::new_Point [expr {($x0 + $x1) / 2}] [expr {($y0 + $y1) / 2}]]
        foreach d {NORTH SOUTH EAST WEST UP DOWN} { $ap setAccess [expr {$d eq $dir}] $d }
        if {[[$ap getLayer] getRoutingLevel] < $lmin} {
            foreach g [$mp getGeometry] { if {[$g getTechLayer] eq $lminl} { $ap setLayer $lminl; incr nlay; break } }
        }
        incr nap; if {![info exists ndir($dir)]} { set ndir($dir) 0 }; incr ndir($dir)
    }
    puts "QB50_MPA small macro pins [array size pins]: access points rewritten $nap (outward [array get ndir]; moved up to $::QC_PNR_MIN_LAYER $nlay), NearbyGrid disabled $ndis"
}
