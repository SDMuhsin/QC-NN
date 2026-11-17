# R14 probe (read-only): which nets does the place-step DRV repair act on, and where are they?  Loads <run>/db/<QB_DB>
# [place] (a run placed without repair, e.g. r11_c), max transition QB_MAXTRAN [0.4] (impl/r5b/pre_place.tcl), placement
# parasitics, then for every max slew / cap / fanout violator pin: its net's terminals (top cells / block pins per
# master), HPWL, bbox -> rpt/drv_nets.txt (one line per net: kind check pin net nterm nblk masters hpwl x1 y1 x2 y2
# drv_master drv_pin).  Summary by impl/r14/drv_sum.py.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qb_env QB_DB place]
set_max_transition [qb_env QB_MAXTRAN 0.4] [current_design]
estimate_parasitics -placement
set blk [ord::get_db_block]
set rf [qb_env QB14_RPT $::OUT/rpt]/drv_viol.tmp
qc_to $rf { report_check_types -max_slew -max_capacitance -max_fanout -violators }
set f [open $rf]; set o [open [qb_env QB14_RPT $::OUT/rpt]/drv_nets.txt w]
set kind slew; array set seen {}
set dbu [$blk getDefUnits]
while {[gets $f line] >= 0} {
    if {[string match "*max slew*" $line]} { set kind slew }
    if {[string match "*max capacitance*" $line]} { set kind cap }
    if {[string match "*max fanout*" $line]} { set kind fanout }
    if {![string match *VIOLATED* $line]} { continue }
    set pin [lindex $line 0]; set k [string last / $pin]
    set net NULL
    if {$k < 0} {
        set bt [$blk findBTerm $pin]; if {$bt ne "NULL"} { set net [$bt getNet] }
    } else {
        set it [$blk findITerm $pin]
        if {$it ne "NULL"} { set net [$it getNet] }
    }
    if {$net eq "NULL"} { puts $o "nonet $kind $pin"; continue }
    set nn [$net getName]
    if {[info exists seen($nn)]} { continue }
    set seen($nn) 1
    set ms {}; set nb 0; set nt 0; set x1 1e12; set y1 1e12; set x2 -1e12; set y2 -1e12; set dm - ; set dp -
    foreach t [$net getITerms] {
        set i [$t getInst]; set m [[$i getMaster] getName]; incr nt
        if {[string match qb_* $m]} { incr nb; lappend ms $m } else { lappend ms std }
        if {[$t isOutputSignal]} { set dm $m; set dp [[$t getMTerm] getName] }
        lassign [$t getAvgXY] ok x y
        if {!$ok} { set b [$i getBBox]; set x [expr {([$b xMin] + [$b xMax]) / 2}]; set y [expr {([$b yMin] + [$b yMax]) / 2}] }
        set x1 [expr {min($x1, $x)}]; set y1 [expr {min($y1, $y)}]; set x2 [expr {max($x2, $x)}]; set y2 [expr {max($y2, $y)}]
    }
    foreach t [$net getBTerms] { incr nt; lappend ms io }
    set ms [lsort -unique $ms]
    puts $o [format "net %s %s %s %d %d %s %.1f %.1f %.1f %.1f %.1f %s %s" $kind $pin $nn $nt $nb [join $ms ,] \
        [expr {double($x2 - $x1 + $y2 - $y1) / $dbu}] [expr {double($x1) / $dbu}] [expr {double($y1) / $dbu}] \
        [expr {double($x2) / $dbu}] [expr {double($y2) / $dbu}] $dm $dp]
}
close $f; close $o
qc_log "r14 probe_drv: [array size seen] nets -> rpt/drv_nets.txt"
