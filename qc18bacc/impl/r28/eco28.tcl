# R28 (results/r28.md): ECO for the DR residue "NS Metal" (LEF57_MINSTEP 0.10 MAXEDGES 1) at off-track macro pins.
# The router lands a 0.10-wide wire on the M3 track crossing a 0.13 x 0.13 macro pin; the wire edge and the pin edge
# leave an overlap 0.07 x 0.065 (< min width 0.10; DRT "NS Metal").  Root cause: these pins lie under a 1.0-um M4 strap
# of the macro PDN grid, so the router cannot drop a VIA34 in the pin and lands on it planar from an M3 track.
# Fix (QB28_ECO_MODE path, default): add an M3 segment on that track across the full pin height (ends flush with the pin
# edges), so wire and pin overlap over the whole pin height.  (QB28_ECO_MODE rect: bounding-box patch; DRT still flags it.)
# Then the rest of impl/r8/dr.tcl after detailed_route (fillers QB8_DR_FILL 0, antenna check, route / finish saves).
#   on tau, in the run dir: QC_PNR_OUT=<run> QC_FLOW=... openroad -exit eco28.tcl   (input db/route_dr.odb,
#   markers rpt/drt.drc.rpt; writes rpt/eco28_pre.rpt / rpt/eco28_post.rpt (check_drc), db/route_dr.odb (patched))
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QB8_DR_THREADS [qc_env QC_PNR_THREADS 8]]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load route_dr
set_propagated_clock [all_clocks]
set blk [ord::get_db_block]; set tech [[ord::get_db] getTech]; set u [$blk getDefUnits]
# markers
set mk {}; set typ ""
set f [open $::OUT/rpt/drt.drc.rpt]
while {[gets $f l] >= 0} {
    if {[regexp {violation type: (.*)$} $l - t]} { set typ [string trim $t] }
    if {[regexp {bbox = \( *([-\d.]+), *([-\d.]+) *\) - \( *([-\d.]+), *([-\d.]+) *\) on Layer (\S+)} $l - a b c d L]} { lappend mk [list $typ $a $b $c $d $L] }
}
close $f
puts "R28_ECO markers [llength $mk]"
# M3-style vertical track grid of a layer: origin / step (dbu)
proc trk {lname} {
    set tg [[ord::get_db_block] findTrackGrid [[[ord::get_db] getTech] findLayer $lname]]
    set p [$tg getGridPatternX 0]; return [list [lindex $p 0] [lindex $p 2]]
}
set chk {}; set np 0; set skip 0
if {[qc_env QB28_ECO_PRE 1]} {
    set nv 0; set n 0
    foreach m $mk {
        lassign $m t a b c d L
        drt::check_drc -box [list [expr {round($a*$u) - 2000}] [expr {round($b*$u) - 2000}] [expr {round($c*$u) + 2000}] [expr {round($d*$u) + 2000}]] -output_file $::OUT/rpt/eco28_pre_$n.rpt
        set g [open $::OUT/rpt/eco28_pre_$n.rpt]; incr nv [regexp -all {violation type} [read $g]]; close $g; incr n
    }
    puts "R28_ECO pre-patch check_drc boxes $n violations $nv"
}
foreach m $mk {
    lassign $m t a b c d L
    set X [expr {round(($a + $c) / 2.0 * $u)}]; set Y [expr {round(($b + $d) / 2.0 * $u)}]
    lappend chk [list [expr {round($a*$u) - 2000}] [expr {round($b*$u) - 2000}] [expr {round($c*$u) + 2000}] [expr {round($d*$u) + 2000}]]
    if {$t ne "NS Metal"} { incr skip; puts "R28_ECO skip $m"; continue }
    set it ""
    foreach i [$blk getInsts] {
        set bb [$i getBBox]
        if {$X < [$bb xMin] || $X > [$bb xMax] || $Y < [$bb yMin] || $Y > [$bb yMax]} continue
        foreach j [$i getITerms] {
            if {[$j getNet] eq "NULL"} continue
            set pb [$j getBBox]
            if {$X >= [$pb xMin] && $X <= [$pb xMax] && $Y >= [$pb yMin] && $Y <= [$pb yMax]} { set it $j; break }
        }
        if {$it ne ""} break
    }
    if {$it eq ""} { incr skip; puts "R28_ECO no pin at $m"; continue }
    set pb [$it getBBox]; set lay [$tech findLayer $L]
    lassign [trk $L] o s; set hw [expr {[$lay getWidth] / 2}]
    set x0 [$pb xMin]; set x1 [$pb xMax]; set k [expr {int(ceil(double($x0 - $o) / $s))}]; set tx [expr {$o + $k * $s}]
    # the wire x from the marker (= wire ∩ pin): its inner x edge is the wire edge (pin access may be off-track)
    set mx0 [expr {round($a * $u)}]; set mx1 [expr {round($c * $u)}]
    if {$mx0 > $x0} { set tx [expr {$mx0 + $hw}] } elseif {$mx1 < $x1} { set tx [expr {$mx1 - $hw}] }
    if {$tx > $x1} { incr skip; puts "R28_ECO no track in pin $m"; continue }
    set px0 [expr {min($x0, $tx - $hw)}]; set px1 [expr {max($x1, $tx + $hw)}]; set py0 [$pb yMin]; set py1 [$pb yMax]
    set net [$it getNet]; set w [$net getWire]
    set e [odb::dbWireEncoder]; $e append $w
    if {[qc_env QB28_ECO_MODE path] eq "rect"} {
        $e newPath $lay ROUTED; $e addPoint $tx $py0
        $e addRect [expr {$px0 - $tx}] 0 [expr {$px1 - $tx}] [expr {$py1 - $py0}]
    } else {   ;# path: track wire across the full pin height (default end extension hw -> ends flush with the pin edges)
        $e newPath $lay ROUTED; $e addPoint $tx [expr {$py0 + $hw}]; $e addPoint $tx [expr {$py1 - $hw}]
    }
    $e end
    incr np
    puts [format "R28_ECO patch %s %s/%s %s track %.3f rect %.3f %.3f %.3f %.3f" [$net getName] [[$it getInst] getName] [[$it getMTerm] getName] $L \
        [expr {$tx / double($u)}] [expr {$px0 / double($u)}] [expr {$py0 / double($u)}] [expr {$px1 / double($u)}] [expr {$py1 / double($u)}]]
}
puts "R28_ECO patched $np skipped $skip"
# opt-in QB28_HOP_OPS "net ops.txt [net2 ops2.txt ...]": replace the net's wire by the op list impl/r28/hop28.py wrote (via hop)
if {[info exists ::env(QB28_HOP_OPS)] && $::env(QB28_HOP_OPS) ne ""} {
  foreach {hn hf} $::env(QB28_HOP_OPS) {
    set net [$blk findNet $hn]
    odb::dbWire_destroy [$net getWire]; set w [odb::dbWire_create $net]; set e [odb::dbWireEncoder]; $e begin $w
    set g [open $hf]; set no 0
    while {[gets $g l] >= 0} {
        set a [lrange $l 1 end]; incr no
        switch -- [lindex $l 0] {
            PATH { $e newPath [$tech findLayer [lindex $a 0]] [lindex $a 1] }
            PT { $e addPoint {*}$a }
            PTX { $e addPoint {*}$a }
            RECT { $e addRect {*}$a }
            VIA { $e addVia [$blk findVia [lindex $a 0]] }
            TVIA { $e addTechVia [$tech findVia [lindex $a 0]] }
            ITERM { $e addITerm [[$blk findInst [lindex $a 0]] findITerm [lindex $a 1]] }
            BTERM { $e addBTerm [$blk findBTerm [lindex $a 0]] }
        }
    }
    close $g; $e end; puts "R28_ECO hop ops $hn: $no ops re-encoded"
  }
}
# opt-in QB28_HOP "net x y0 y1 via": two-net crossing on a lower layer left by DRT.  The net's vertical segment at x
# that spans [y0, y1] is re-encoded as lower layer -> via up at y0 -> upper layer to y1 -> via down (wire rebuilt from
# its decoded ops; only PATH / POINT / POINT_EXT / VIA / TECH_VIA / RECT / ITERM / BTERM are supported).
proc r28_hop {net hx y0 y1 vname} {
    set tech [[ord::get_db] getTech]; set via [$tech findVia $vname]; set w [$net getWire]
    set d [odb::dbWireDecoder]; $d begin $w; set ops {}
    while {[set op [$d next]] != $::odb::dbWireDecoder_END_DECODE} {
        switch -- $op {
            0 { lappend ops [list PATH [$d getLayer] [$d getWireType]] }
            4 { lappend ops [list PT {*}[$d getPoint]] }
            5 { lappend ops [list PTX {*}[$d getPoint]] }
            6 { lappend ops [list VIA [$d getVia]] }
            7 { lappend ops [list TVIA [$d getTechVia]] }
            8 { lappend ops [list RECT {*}[$d getRect]] }
            9 { lappend ops [list ITERM [$d getITerm]] }
            10 { lappend ops [list BTERM [$d getBTerm]] }
            11 { }
            default { puts "R28_ECO hop: unsupported wire opcode $op on [$net getName]"; return 0 }
        }
    }
    # find PATH, PT (hx, ya), PT (hx, yb) with ya <= y0 < y1 <= yb (or reversed) on the via's bottom layer
    set lo [$via getBottomLayer]; set n [llength $ops]; set k -1
    for {set i 0} {$i + 2 < $n} {incr i} {
        lassign [lindex $ops $i] o l; lassign [lindex $ops [expr {$i+1}]] o1 xa ya; lassign [lindex $ops [expr {$i+2}]] o2 xb yb
        if {$o eq "PATH" && $l eq $lo && $o1 eq "PT" && $o2 eq "PT" && $xa == $hx && $xb == $hx && min($ya,$yb) <= $y0 && max($ya,$yb) >= $y1} { set k $i; break }
    }
    if {$k < 0} { puts "R28_ECO hop: segment not found on [$net getName]"; return 0 }
    lassign [lindex $ops [expr {$k+1}]] - - ya; lassign [lindex $ops [expr {$k+2}]] - - yb
    if {$ya > $yb} { lassign [list $y1 $y0] y0 y1 }        ;# walk in the segment's direction
    set rep [list [lindex $ops $k] [lindex $ops [expr {$k+1}]] [list PT $hx $y0] [list TVIA $via] [list PT $hx $y1] [list TVIA $via] [lindex $ops [expr {$k+2}]]]
    set ops [lreplace $ops $k [expr {$k+2}] {*}$rep]
    odb::dbWire_destroy $w; set w [odb::dbWire_create $net]; set e [odb::dbWireEncoder]; $e begin $w
    foreach o $ops {
        switch -- [lindex $o 0] {
            PATH { $e newPath [lindex $o 1] [lindex $o 2] }
            PT { $e addPoint [lindex $o 1] [lindex $o 2] }
            PTX { $e addPoint [lindex $o 1] [lindex $o 2] [lindex $o 3] }
            VIA { $e addVia [lindex $o 1] }
            TVIA { $e addTechVia [lindex $o 1] }
            RECT { $e addRect {*}[lrange $o 1 4] }
            ITERM { $e addITerm [lindex $o 1] }
            BTERM { $e addBTerm [lindex $o 1] }
        }
    }
    $e end; return 1
}
if {[info exists ::env(QB28_HOP)] && $::env(QB28_HOP) ne ""} {
    lassign $::env(QB28_HOP) hn hx hy0 hy1 hv
    puts "R28_ECO hop [$blk findNet $hn] $hn $hx $hy0 $hy1 $hv -> [r28_hop [$blk findNet $hn] $hx $hy0 $hy1 $hv]"
}
# opt-in QB28_RR_NETS "n1 n2 ..": remove these nets' routing and let DRT route them again (QB28_RR_ITER [8] iterations)
# on top of the existing routing (DRT on a routed db), for a two-net short the router left behind.
if {[info exists ::env(QB28_RR_NETS)] && $::env(QB28_RR_NETS) ne ""} {
    foreach nn $::env(QB28_RR_NETS) { set n [$blk findNet $nn]; set w [$n getWire]; if {$w ne "NULL"} { odb::dbWire_destroy $w }; puts "R28_ECO rr ripup $nn" }
    set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
    read_guides $::OUT/route.guide
    set t [clock seconds]
    detailed_route -output_drc $::OUT/rpt/eco28_drt.rpt -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
        -droute_end_iter [qc_env QB28_RR_ITER 8] -verbose 1
    puts "R28_ECO rr detailed_route [expr {[clock seconds] - $t}] s"
}
set n 0; set nv 0
foreach bx $chk {
    drt::check_drc -box $bx -output_file $::OUT/rpt/eco28_post_$n.rpt
    set g [open $::OUT/rpt/eco28_post_$n.rpt]; set v [regexp -all {violation type} [read $g]]; close $g
    incr nv $v; incr n
}
puts "R28_ECO post-patch check_drc boxes $n violations $nv"
if {[qc_env QB28_ECO_FULL 1]} {
    set t [clock seconds]; drt::check_drc -output_file $::OUT/rpt/eco28_full.rpt
    set g [open $::OUT/rpt/eco28_full.rpt]; set nf [regexp -all {violation type} [read $g]]; close $g
    puts "R28_ECO full-die check_drc violations $nf ([expr {[clock seconds] - $t}] s)"
    # pass 2 (QB28_ECO_NOTCH 1, off by default: ineffective, see below): same-net "Metal Spacing" (one source net, gap < min spacing between two shapes of the
    # net, not in DRT's own final report): fill the gap box (= marker bbox) with metal of that net.
    if {$nf > 0 && [qc_env QB28_ECO_NOTCH 0]} {
        set g [open $::OUT/rpt/eco28_full.rpt]; set typ ""; set src ""; set nn 0
        while {[gets $g l] >= 0} {
            if {[regexp {violation type: (.*)$} $l - x]} { set typ [string trim $x] }
            if {[regexp {srcs: (.*)$} $l - x]} { set src [string trim $x] }
            if {[regexp {bbox = \( *([-\d.]+), *([-\d.]+) *\) - \( *([-\d.]+), *([-\d.]+) *\) on Layer (\S+)} $l - a b c d L]} {
                if {$typ ne "Metal Spacing" || [llength $src] != 1 || ![string match net:* $src]} { puts "R28_ECO notch skip $typ $src $a $b $c $d $L"; continue }
                set X0 [expr {round($a*$u)}]; set Y0 [expr {round($b*$u)}]; set X1 [expr {round($c*$u)}]; set Y1 [expr {round($d*$u)}]
                if {$X1 <= $X0 || $Y1 <= $Y0} continue
                set net [$blk findNet [string range $src 4 end]]; set lay [$tech findLayer $L]
                set e [odb::dbWireEncoder]; $e append [$net getWire]; $e newPath $lay ROUTED; $e addPoint $X0 $Y0
                $e addRect 0 0 [expr {$X1 - $X0}] [expr {$Y1 - $Y0}]; $e end; incr nn
                puts "R28_ECO notch fill [$net getName] $L $a $b $c $d"
            }
        }
        close $g
        drt::check_drc -output_file $::OUT/rpt/eco28_full2.rpt
        set g [open $::OUT/rpt/eco28_full2.rpt]; set nf [regexp -all {violation type} [read $g]]; close $g
        puts "R28_ECO notch fills $nn, full-die check_drc after pass 2: $nf"
    }
    # check_drc of this build does not load the routes' RECT patches (DRT's own patches; a RECT fill changes nothing):
    # its extra same-net markers are not in DRT's final count.  Gate on them only with QB28_ECO_FULL_GATE 1.
    if {[qc_env QB28_ECO_FULL_GATE 0]} { incr nv $nf }
}
if {[qc_env QB28_ECO_SAVE 1] && $nv == 0} {
    qc_save route_dr
    set fill [concat [expr {[p DCAP] ? $::QC_PNR_DCAP : {}}] [expr {[p FILL] ? $::QC_PNR_FILL : {}}]]
    if {[llength $fill] && ![qc_env QB8_DR_FILL 1]} { filler_placement $fill; qc_log "r28 eco: fillers after detailed_route" }
    if {[p ANTENNA_CHECK]} { check_antennas -verbose }
    qc_save route
    source $::env(QC_FLOW)/pnr/or/finish.tcl
    qc_save finish
    puts "R28_ECO saved route_dr / route / finish"
}
qc_log "r28 eco done [expr {[clock seconds] - $::T0}] s"
exit
