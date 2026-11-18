# R24 (results/r24.md): clock-tree census of a hub checkpoint (QB_DB [cts]): buffers on clock nets by name class and
# master, register sinks behind each class of repair_clock_nets / wire buffer (max_length*, wire*), and the CTS latency
# split gated (behind a CKLNQD) vs ungated register clock pins (sta arrival at CP, ns) -> stdout R24_CLK lines.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env QB_DB cts]
estimate_parasitics -placement
array set C {}
set nsk 0
foreach i [[ord::get_db_block] getInsts] {
    set m [[$i getMaster] getName]
    if {![regexp {^(CKBD|CKND|BUFF|INVD|CKLN)} $m]} continue
    set clk 0
    foreach it [$i getITerms] {
        if {[$it isOutputSignal] || [$it getIoType] eq "OUTPUT"} {
            set n [$it getNet]; if {$n ne "NULL" && [$n getSigType] eq "CLOCK"} { set clk 1 }
        }
    }
    if {!$clk} continue
    set cls [regsub -all {[0-9_]+} [lindex [split [$i getName] /] end] N]
    if {[string match *clk_gate* [$i getName]]} { set cls icg }
    set k "$cls:$m"; if {![info exists C($k)]} { set C($k) 0 }; incr C($k)
}
foreach k [lsort [array names C]] { if {$C($k) >= 5 || [string match max* $k]} { puts "R24_CLK buf $k $C($k)" } }
# latency of register clock pins, gated vs ungated (gated = the CP net tree is driven through a CKLNQD)
proc qb24_gated {pin} {
    set n [[[ord::get_db_block] findITerm $pin] getNet]
    for {set d 0} {$d < 30 && $n ne "NULL"} {incr d} {
        set drv ""
        foreach it [$n getITerms] { if {[$it isOutputSignal] || [$it getIoType] eq "OUTPUT"} { set drv $it } }
        if {$drv eq ""} { return 0 }
        set di [$drv getInst]; set m [[$di getMaster] getName]
        if {[string match CKLN* $m]} { return 1 }
        set n "NULL"; foreach it [$di getITerms] { if {[$it isInputSignal] && [$it getNet] ne "NULL" && [[$it getNet] getSigType] eq "CLOCK"} { set n [$it getNet] } }
    }
    return 0
}
set k 0; array set L {g,n 0 g,s 0 g,mx 0 u,n 0 u,s 0 u,mx 0 g,mn 9 u,mn 9}
foreach p [get_pins -hierarchical */CP] {
    incr k; if {$k % 7} continue
    set nm [get_full_name $p]
    if {[catch { set a [get_property $p arrival_max_rise] }] || $a eq ""} continue
    if {abs($a) < 1e-3} { set a [expr {$a * 1e9}] }
    if {[catch { set g [expr {[qb24_gated $nm] ? "g" : "u"}] }]} continue
    incr L($g,n); set L($g,s) [expr {$L($g,s) + $a}]
    if {$a > $L($g,mx)} { set L($g,mx) $a }; if {$a < $L($g,mn)} { set L($g,mn) $a }
}
foreach g {g u} { if {$L($g,n)} { puts [format "R24_CLK lat %s n %d mean %.3f min %.3f max %.3f (1/7 sample)" $g $L($g,n) [expr {$L($g,s)/$L($g,n)}] $L($g,mn) $L($g,mx)] } }
exit
