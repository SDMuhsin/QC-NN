# impl/r6c spread3 (QB_SPREAD3 1): replaces impl/r6b spread2 (which moved 64.7 k of 159 k cells by a mean of 5
# 100-um super-bins to a random point: 21 k repair buffers detour > 300 um, 8.7 k > 1 mm, probe_rows.tcl).
# Bins QB_SPREAD_BX um (20) x one row, capacity = row length x QB_SPREAD_FILL (0.92); occupancy = the cells that stay
# (master unchanged since the last record, ::QB6_M); every other placed std cell stays if its own bin has room, else
# goes to the nearest bin with room (offsets sorted by distance up to QB_SPREAD_R um, 400), at the point of that bin
# closest to its location.  The offset scan of a source bin restarts where its previous cell found room (bins only fill).
proc qb6c_spread3 {} {
    set t0 [clock milliseconds]
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set bx [expr {round([qb_env QB_SPREAD_BX 20.0] * $u)}]
    set fill [qb_env QB_SPREAD_FILL 0.92]
    set rh [[[lindex [$blk getRows] 0] getSite] getHeight]; set sw [[[lindex [$blk getRows] 0] getSite] getWidth]
    set core [$blk getCoreArea]; set cx0 [$core xMin]; set cy0 [$core yMin]
    array set cap {}; array set occ {}; array set seg {}; array set rowo {}
    foreach rw [$blk getRows] {
        set b [$rw getBBox]
        set j [expr {([$b yMin] - $cy0) / $rh}]
        set rowo($j) [list [$b yMin] [$rw getOrient]]
        for {set x [$b xMin]} {$x < [$b xMax]} {} {
            set i [expr {($x - $cx0) / $bx}]
            set xe [expr {min([$b xMax], $cx0 + ($i + 1) * $bx)}]
            set k "$i,$j"
            if {[info exists cap($k)]} { set cap($k) [expr {$cap($k) + ($xe - $x) * $fill}]; lappend seg($k) $x $xe } else { set cap($k) [expr {($xe - $x) * $fill}]; set occ($k) 0; set seg($k) [list $x $xe] }
            set x $xe
        }
    }
    set mov {}
    foreach i [$blk getInsts] {
        set m [$i getMaster]
        if {[$m isBlock] || [$i getPlacementStatus] ne "PLACED"} continue
        if {[info exists ::QB6_M($i)] && $::QB6_M($i) eq [$m getName]} {
            lassign [$i getLocation] x y
            set k "[expr {($x - $cx0) / $bx}],[expr {($y - $cy0) / $rh}]"
            if {[info exists occ($k)]} { set occ($k) [expr {$occ($k) + [$m getWidth]}] }
        } else { lappend mov $i }
    }
    set rr [expr {[qb_env QB_SPREAD_R 400.0] * $u}]
    set nx [expr {int($rr / $bx)}]; set ny [expr {int($rr / $rh)}]
    set offs {}
    for {set dx -$nx} {$dx <= $nx} {incr dx} { for {set dy -$ny} {$dy <= $ny} {incr dy} {
        set d [expr {hypot($dx * $bx, $dy * $rh)}]; if {$d <= $rr} { lappend offs [list $d $dx $dy] } } }
    set offs [lsort -real -index 0 $offs]
    set no [llength $offs]
    set od {}; set ox {}; set oy {}
    foreach o $offs { lappend od [lindex $o 0]; lappend ox [lindex $o 1]; lappend oy [lindex $o 2] }
    array set ptr {}; set failed {}
    set nk 0; set nm 0; set fail 0; set dsum 0.0; set d100 0
    foreach i $mov {
        set w [[$i getMaster] getWidth]
        lassign [$i getLocation] x y
        set bi [expr {($x - $cx0) / $bx}]; set bj [expr {($y - $cy0) / $rh}]
        set k0 "$bi,$bj"
        if {[info exists cap($k0)] && $occ($k0) + $w <= $cap($k0)} { set occ($k0) [expr {$occ($k0) + $w}]; incr nk; continue }
        set p [expr {[info exists ptr($k0)] ? $ptr($k0) : 1}]
        set done 0
        for {} {$p < $no} {incr p} {
            set ki [expr {$bi + [lindex $ox $p]}]; set kj [expr {$bj + [lindex $oy $p]}]
            set k "$ki,$kj"
            if {![info exists cap($k)] || $occ($k) + $w > $cap($k)} continue
            # closest point of the bin's row segments to x
            set best ""; set bd 0
            foreach {s1 s2} $seg($k) {
                if {$s2 - $s1 < $w} continue
                set xn [expr {max($s1, min($s2 - $w, $x))}]
                if {$best eq "" || abs($xn - $x) < $bd} { set best $xn; set bd [expr {abs($xn - $x)}] }
            }
            if {$best eq ""} continue
            set best [expr {$best - ($best - $cx0) % $sw}]
            if {$best < [lindex $seg($k) 0]} { incr best $sw }
            $i setLocation $best [lindex $rowo($kj) 0]; $i setOrient [lindex $rowo($kj) 1]
            set occ($k) [expr {$occ($k) + $w}]
            set dd [lindex $od $p]; set dsum [expr {$dsum + $dd}]; if {$dd > 100 * $u} { incr d100 }
            incr nm; set done 1; break
        }
        set ptr($k0) $p
        if {!$done} { incr fail; lappend failed $i }
    }
    # fallback (QB_SPREAD3_FB 1): nearest QB_SPREAD_SB-um (100) super-bin with free capacity anywhere on the die,
    # then the fine bin of it with room closest to the cell (never a random point)
    set nf 0; set fsum 0.0
    # cells without room within QB_SPREAD_R: name and location (um) before the fallback, rpt/spread3_fail_<k>.txt
    if {[info exists ::OUT] && [llength $failed]} {
        if {![info exists ::QB6C_NF]} { set ::QB6C_NF 0 }
        set fh [open $::OUT/rpt/spread3_fail_[incr ::QB6C_NF].txt w]
        foreach i $failed { lassign [$i getLocation] x y; puts $fh "[$i getName] [[$i getMaster] getName] [expr {$x / $u}] [expr {$y / $u}]" }
        close $fh
    }
    if {[qb_env QB_SPREAD3_FB 1] && [llength $failed]} {
        set sbn [expr {round([qb_env QB_SPREAD_SB 100.0] * $u)}]
        array set sfree {}; array set sbins {}
        foreach k [array names cap] {
            lassign [split $k ,] i j
            set sk "[expr {($i * $bx) / $sbn}],[expr {($j * $rh) / $sbn}]"
            if {![info exists sfree($sk)]} { set sfree($sk) 0 }
            set sfree($sk) [expr {$sfree($sk) + $cap($k) - $occ($k)}]; lappend sbins($sk) $k
        }
        set snx [expr {[$core dx] / $sbn + 1}]; set sny [expr {[$core dy] / $sbn + 1}]
        set soff {}
        for {set dx -$snx} {$dx <= $snx} {incr dx} { for {set dy -$sny} {$dy <= $sny} {incr dy} { lappend soff [list [expr {hypot($dx, $dy)}] $dx $dy] } }
        set soff [lsort -real -index 0 $soff]
        array set sptr {}
        foreach i $failed {
            set w [[$i getMaster] getWidth]
            lassign [$i getLocation] x y
            set si [expr {($x - $cx0) / $sbn}]; set sj [expr {($y - $cy0) / $sbn}]
            set s0 "$si,$sj"
            set p [expr {[info exists sptr($s0)] ? $sptr($s0) : 0}]
            set done 0
            for {} {$p < [llength $soff]} {incr p} {
                set o [lindex $soff $p]
                set sk "[expr {$si + [lindex $o 1]}],[expr {$sj + [lindex $o 2]}]"
                if {![info exists sfree($sk)] || $sfree($sk) < 4 * $w} continue
                set bk ""; set bd 0
                foreach k $sbins($sk) {
                    if {$occ($k) + $w > $cap($k)} continue
                    lassign [split $k ,] ki kj
                    set d [expr {abs($cx0 + $ki * $bx - $x) + abs($cy0 + $kj * $rh - $y)}]
                    if {$bk eq "" || $d < $bd} { set bk $k; set bd $d }
                }
                if {$bk eq ""} { set sfree($sk) 0; continue }
                lassign [split $bk ,] ki kj
                lassign $seg($bk) s1 s2
                set xn [expr {max($s1, min($s2 - $w, $x))}]; set xn [expr {$xn - ($xn - $cx0) % $sw}]; if {$xn < $s1} { incr xn $sw }
                $i setLocation $xn [lindex $rowo($kj) 0]; $i setOrient [lindex $rowo($kj) 1]
                set occ($bk) [expr {$occ($bk) + $w}]; set sfree($sk) [expr {$sfree($sk) - $w}]
                set fsum [expr {$fsum + $bd}]; incr nf; set done 1; break
            }
            set sptr($s0) $p
        }
    }
    qc_log [format "r6c: spread3 fallback %d of %d cells placed (mean %.0f um)" $nf [llength $failed] [expr {$fsum / max(1, $nf) / $u}]]
    qc_log [format "r6c: spread3 %d movable cells: %d kept, %d moved (mean %.1f um, %d > 100 um), %d without room within %g um, %.1f s" \
        [llength $mov] $nk $nm [expr {$dsum / max(1, $nm) / $u}] $d100 $fail [qb_env QB_SPREAD_R 400.0] [expr {([clock milliseconds] - $t0) / 1000.0}]]
}
proc qb6_spread2 {} { qb6c_spread3 }
qc_log "r6c: spread3 replaces spread2"
