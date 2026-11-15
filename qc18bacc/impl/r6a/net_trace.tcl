# impl/r6a (H1): attribute every buffer / inverter of a placed chip checkpoint to the root net it buffers (driver = a
# non-buffer cell or a chip IO), with the root tree's placed extent.  QB_RUN, QB_DB (default place), QB_OUT (text).
# One line per root net that has >= 1 buffer / inverter in its tree or HPWL >= 500 um:
#   R <root net> <driver inst | PORT> <driver master> <n leaf sinks> <n buf/inv> <n buf/inv inserted by rsz (wire / fanout / max_length / load_slew / max_cap names)> <buf area um2>
#     <hpwl um of driver + leaf pins> <leaf groups (<= 8)>
read_db $::env(QB_RUN)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "place"}].odb
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
proc isbuf {m} { return [regexp {^(BUFF|CKBD|INVD|CKND|DEL)} [$m getName]] }
proc grp {i} {
    set m [$i getMaster]; set mn [$m getName]
    if {$mn eq "qb_col_blk"} { return "BLK" }
    if {[$m isBlock]} { regexp {^([a-z]+_[a-z]+)} $mn -> p; return "MAC:$mn" }
    set n [$i getName]; set p [split $n /]
    if {[llength $p] >= 3} { return [join [lrange $p 0 1] /] } elseif {[llength $p] == 2} { return [lindex $p 0] }
    return top
}
proc ctr {i} { set b [$i getBBox]; return [list [expr {([$b xMin] + [$b xMax]) / 2}] [expr {([$b yMin] + [$b yMax]) / 2}]] }
set fo [open $::env(QB_OUT) w]
set nroot 0
foreach net [$blk getNets] {
    set st [$net getSigType]; if {$st eq "POWER" || $st eq "GROUND"} continue
    # driver
    set drv ""; set dm ""; set xy ""
    foreach it [$net getITerms] { if {[$it isOutputSignal]} { set drv [$it getInst]; break } }
    if {$drv ne ""} {
        if {[isbuf [$drv getMaster]]} continue
        set dname [$drv getName]; set dm [[$drv getMaster] getName]; set xy [ctr $drv]
    } else {
        set bts [$net getBTerms]; if {[llength $bts] == 0} continue
        set bt [lindex $bts 0]; if {[$bt getIoType] ne "INPUT"} continue
        set dname PORT; set dm [$bt getName]; set b [$bt getBBox]
        set xy [list [expr {([$b xMin] + [$b xMax]) / 2}] [expr {([$b yMin] + [$b yMax]) / 2}]]
    }
    set x0 [lindex $xy 0]; set x1 $x0; set y0 [lindex $xy 1]; set y1 $y0
    set nb 0; set nr 0; set ba 0.0; set nl 0; array unset G; set stack [list $net]
    while {[llength $stack]} {
        set n [lindex $stack end]; set stack [lrange $stack 0 end-1]
        foreach it [$n getITerms] {
            if {![$it isInputSignal]} continue
            set i [$it getInst]; set m [$i getMaster]
            if {[isbuf $m]} {
                incr nb; set ba [expr {$ba + [$m getWidth] / $u * [$m getHeight] / $u}]
                if {[regexp {^(wire|fanout|max_length|load_slew|max_cap|split|rebuffer|gain)[0-9]} [lindex [split [$i getName] /] end]]} { incr nr }
                foreach o [$i getITerms] { if {[$o isOutputSignal] && [$o getNet] ne "NULL"} { lappend stack [$o getNet] } }
            } else {
                incr nl; set G([grp $i]) 1
                lassign [ctr $i] x y
                if {$x < $x0} {set x0 $x}; if {$x > $x1} {set x1 $x}; if {$y < $y0} {set y0 $y}; if {$y > $y1} {set y1 $y}
            }
        }
        foreach bt [$n getBTerms] {
            if {[$bt getIoType] eq "OUTPUT"} { incr nl; set G(PORT_OUT) 1 }
        }
    }
    set hp [expr {(($x1 - $x0) + ($y1 - $y0)) / $u}]
    incr nroot
    if {$nb > 0 || $hp >= 500} {
        puts $fo "R [$net getName] $dname $dm $nl $nb $nr [format %.1f $ba] [format %.0f $hp] [join [lrange [lsort [array names G]] 0 7] ,]"
    }
}
array set H {}
foreach i [$blk getInsts] { if {[isbuf [$i getMaster]]} { regsub -all {[0-9]+} [lindex [split [$i getName] /] end] N k; incr H($k) } }
foreach k [array names H] { puts $fo "H $k $H($k)" }
close $fo
puts "NET_TRACE roots $nroot done"
exit
