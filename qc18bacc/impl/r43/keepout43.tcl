# R43 (results/r43.md, R41 bug 1): placement keep-out that OpenROAD 2.0-12381 actually enforces.
# q43_keepout x1 y1 x2 y2 (DBU): every dbRow that overlaps the rectangle is split, the sites inside it removed (gpl
# sees no rows there, DPL / repair cannot legalise into it), and the rectangle is recorded in ::Q43_KO.
# check_placement is wrapped once: after the original check, any non-block instance overlapping a ::Q43_KO rectangle
# is listed and the step FAILS (error), so the place / CTS / post-GRT legalisations are all covered.
if {![info exists ::Q43_KO]} { set ::Q43_KO {} }
proc q43_keepout {x1 y1 x2 y2} {
    set b [ord::get_db_block]; set u [$b getDefUnits]; set ncut 0; set nnew 0; set srm 0
    foreach r [$b getRows] {
        set bb [$r getBBox]
        if {[$bb yMax] <= $y1 || [$bb yMin] >= $y2 || [$bb xMax] <= $x1 || [$bb xMin] >= $x2} { continue }
        set site [$r getSite]; lassign [$r getOrigin] ox oy; set sp [$r getSpacing]; set n [$r getSiteCount]
        set or [$r getOrient]; set dir [$r getDirection]; set nm [$r getName]
        # sites [0, kl) left of x1, [kr, n) right of x2
        set kl [expr {max(0, min($n, int(floor(double($x1 - $ox) / $sp))))}]
        set kr [expr {max(0, min($n, int(ceil(double($x2 - $ox) / $sp))))}]
        odb::dbRow_destroy $r; incr ncut; incr srm [expr {$kr - $kl}]
        if {$kl > 0} { odb::dbRow_create $b ${nm}_q43l $site $ox $oy $or $dir $kl $sp; incr nnew }
        if {$kr < $n} { odb::dbRow_create $b ${nm}_q43r $site [expr {$ox + $kr * $sp}] $oy $or $dir [expr {$n - $kr}] $sp; incr nnew }
    }
    lappend ::Q43_KO [list $x1 $y1 $x2 $y2]
    qc_log [format "r43 keepout %.2f %.2f %.2f %.2f um: %d rows split into %d, %d sites removed" \
        [expr {$x1 / double($u)}] [expr {$y1 / double($u)}] [expr {$x2 / double($u)}] [expr {$y2 / double($u)}] $ncut $nnew $srm]
    qc_summary "r43 keepout rows_split $ncut sites_removed $srm"
}
# number of non-block instances overlapping a keep-out (first 10 listed in the log)
proc q43_ko_count {} {
    set b [ord::get_db_block]; set n 0
    foreach i [$b getInsts] {
        if {[[$i getMaster] isBlock] || ![$i isPlaced]} { continue }
        set bb [$i getBBox]
        foreach k $::Q43_KO {
            lassign $k x1 y1 x2 y2
            if {[$bb xMax] > $x1 && [$bb xMin] < $x2 && [$bb yMax] > $y1 && [$bb yMin] < $y2} {
                if {[incr n] <= 10} { qc_log "r43 keepout overlap: [$i getName] [[$i getMaster] getName] [$bb xMin] [$bb yMin]" }
                break
            }
        }
    }
    return $n
}
if {[info commands q43_cp_orig] eq ""} {
    rename check_placement q43_cp_orig
    proc check_placement {args} {
        uplevel 1 [list q43_cp_orig {*}$args]
        set n [q43_ko_count]
        qc_summary "r43 keepout_check overlaps $n"
        if {$n > 0} { error "R43_FAIL keep-out: $n instances overlap [llength $::Q43_KO] keep-out rectangle(s)" }
    }
}
