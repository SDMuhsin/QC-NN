# R11 proposal A (results/r8d.md) after CTS (PRE_ROUTE hook, QB11_PROPA 1): the column clk pins move up the top clock
# tree to the net whose arrival is closest to (median top register clock arrival - QB11_INS [0.96 ns tt = R5d block
# insertion]), so the column flops (clk pin + insertion) are balanced with the top registers.  CTS -insertion_delay
# (the ETM clock-tree-path arcs) is not usable: TritonCTS then traces only 2 clock nets and OpenSTA finds no clocked
# path (R5b, reproduced in r11_c).  Writes rpt/propa.txt (per column: arrival before / after, levels moved).
proc qb11_arr {name} {
    set p [get_pins -quiet $name]
    if {$p eq ""} { return "" }
    set best ""
    foreach v [$p vertices] {
        if {$v eq "NULL"} { continue }
        set path [sta::vertex_worst_arrival_path $v max]
        if {$path eq "NULL" || $path eq ""} { continue }
        set a [$path arrival]
        if {abs($a) < 1e-6} { set a [expr {$a * 1e9}] }
        if {$best eq "" || $a > $best} { set best $a }
    }
    return $best
}
proc qb11_num {a} { return [expr {$a eq "" ? -1.0 : $a}] }
proc qb11_propa {} {
    set ins [qb_env QB11_INS 0.96]
    estimate_parasitics -placement
    report_worst_slack -max ;# forces the arrival update (vertex_worst_arrival_path reads cached arrivals)
    set blk [ord::get_db_block]
    # reference: median clock arrival of a sample of top register clock pins
    set l {}; set k 0
    foreach i [$blk getInsts] {
        set m [[$i getMaster] getName]
        if {![string match DF* $m] && ![string match EDF* $m]} { continue }
        if {[incr k] % 50} { continue }
        set a [qb11_arr "[$i getName]/CP"]
        if {$a ne ""} { lappend l $a }
        if {[llength $l] >= 600} { break }
    }
    set l [lsort -real $l]; set ref [lindex $l [expr {[llength $l] / 2}]]
    set f [open $::OUT/rpt/propa.txt w]
    puts $f [format "# R11 proposal A: top register clock arrival median %.3f ns (n %d, min %.3f max %.3f), target column clk pin = median - %.2f" $ref [llength $l] [lindex $l 0] [lindex $l end] $ins]
    set tgt [expr {$ref - $ins}]
    foreach it [$blk getITerms] { }
    foreach i [$blk getInsts] {
        if {[[$i getMaster] getName] ne "qb_col_blk"} { continue }
        set ck [$i findITerm clk]; set net [$ck getNet]
        set a0 [qb11_arr "[$i getName]/clk"]
        set cur $net; set lv 0; set best $net; set bestd 1e9
        while {$cur ne "NULL"} {
            set d [$cur getFirstOutput]
            if {$d eq "NULL"} { break }
            set di [$d getInst]
            set an [qb11_arr "[$di getName]/[[$d getMTerm] getName]"]
            if {$an ne "" && abs($an - $tgt) < $bestd} { set bestd [expr {abs($an - $tgt)}]; set best $cur; set blv $lv }
            if {$an ne "" && $an < $tgt} { break }
            set inp NULL
            foreach t [$di getITerms] { if {[$t isInputSignal] && [$t getNet] ne "NULL"} { set inp $t; break } }
            if {$inp eq "NULL"} { break }
            set cur [$inp getNet]; incr lv
        }
        if {$best ne $net} { $ck disconnect; $ck connect $best }
        puts $f [format "%s clk arrival %.3f -> tap net %s (%d levels up, driver arrival ~%.3f)" [$i getName] [qb11_num $a0] [$best getName] [expr {[info exists blv] ? $blv : 0}] [expr {$tgt + 0}]]
        unset -nocomplain blv
    }
    estimate_parasitics -placement
    report_worst_slack -max
    foreach i [$blk getInsts] {
        if {[[$i getMaster] getName] eq "qb_col_blk"} { puts $f [format "%s clk arrival after %.3f" [$i getName] [qb11_num [qb11_arr "[$i getName]/clk"]]] }
    }
    close $f
    qc_log "r11 propa: ref [format %.3f $ref] target [format %.3f $tgt] (rpt/propa.txt)"
}
if {[qb_env QB11_PROPA 1]} { qb11_propa }
