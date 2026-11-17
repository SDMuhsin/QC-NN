# PRE_PLACE_TCL of impl/r19/act.cfg: impl/r13/place.tcl (S1 padding + r9a edge chains + r7c gpl_incr2) and, outermost
# around global_placement, the R19 band seed (QB19_SEED, default 1): on the first (non-incremental) call every band cell
# (band.tcl) is put at a random point of its act-row band (x uniform over the core), and gpl starts from there
# (FIRM while gpl's initial quadratic placement places the other cells around them; then Nesterov with -skip_initial_place
# and every cell movable: no initial placement that would pull the lb words back to the middle).  The band
# structure is then held by the netlist itself (lb word -> its band's pre-mux / partials only; cascade to the
# neighbour bands; s1 registers -> S2 -> act at the row).  Band statistics before / after: summary 'r19 bands'.
source $::QB13_DIR/place.tcl
source $::QB19_DIR/band.tcl
if {[info commands qb19_gpl_orig] eq ""} {
    rename global_placement qb19_gpl_orig
    proc global_placement {args} {
        if {[lsearch $args -incremental] < 0 && ![info exists ::QB19_DONE] && [qb_env QB19_SEED 1]} {
            set ::QB19_DONE 1
            set blk [ord::get_db_block]; set core [$blk getCoreArea]
            set pj [qb19_pj]; set B [qb19_bands]
            expr {srand([qb_env QB19_RSEED 19])}
            set k 0; set seeded {}
            set bh [qb_env QB19_BH 1.0]
            foreach i [$blk getInsts] {
                if {[$i getPlacementStatus] in {FIRM LOCKED COVER}} { continue }
                set b [qb19_band_of [$i getName] $pj]
                if {$b < 0} { continue }
                lassign [lindex $B $b] a c yc
                set h [expr {($c - $a) * $bh}]
                set x [expr {[$core xMin] + int(rand() * ([$core dx] - [[$i getMaster] getWidth]))}]
                set y [expr {int($yc - $h / 2 + rand() * $h)}]
                set y [expr {min(max($y, [$core yMin]), [$core yMax] - [[$i getMaster] getHeight])}]
                $i setLocation $x $y; $i setPlacementStatus FIRM
                lappend seeded $i
                incr k
            }
            qc_summary "r19 band seed cells $k bands [llength $B] y0_um [expr {[lindex $B 0 0] / double([[ord::get_db_tech] getDbUnitsPerMicron])}]"
            qb19_stats seed
            # initial (quadratic) placement of the other cells with the band cells as fixed anchors, then Nesterov
            # from there with every cell movable
            qb19_gpl_orig {*}$args -skip_nesterov_place
            foreach i $seeded { $i setPlacementStatus PLACED }
            qb19_gpl_orig {*}$args -skip_initial_place
            qb19_stats gpl
            return
        }
        qb19_gpl_orig {*}$args
    }
}
