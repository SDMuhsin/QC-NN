# R25: 50 um bin dump of a hub checkpoint (QB_DB [grt]) for the DR marker map (an25.py); files in $QB25_OUT (on tau):
#   bins.txt  ix iy std_area_um2 n_std n_sigpins (std cells by bbox centre; pins = ITerms on non-supply nets)
#   mac.txt   name master x0 y0 x1 y1 (um);  mpin.txt macro xc yc (macro ITerms on nets);  bterm.txt name xc yc
set db [ord::get_db]
read_db $::env(QC_PNR_OUT)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "grt"}].odb
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]; set bs [expr {50.0 * $u}]
set die [$blk getDieArea]
set o $::env(QB25_OUT)
set fm [open $o/mac.txt w]; set fp [open $o/mpin.txt w]; set fb [open $o/bterm.txt w]
puts $fm "DIE [expr {[$die xMin]/$u}] [expr {[$die yMin]/$u}] [expr {[$die xMax]/$u}] [expr {[$die yMax]/$u}]"
array set A {}; array set N {}; array set P {}
set t [clock seconds]
foreach i [$blk getInsts] {
    set m [$i getMaster]; set bb [$i getBBox]
    set x0 [$bb xMin]; set y0 [$bb yMin]; set x1 [$bb xMax]; set y1 [$bb yMax]
    if {[$m isBlock]} {
        puts $fm "[$i getName] [$m getName] [expr {$x0/$u}] [expr {$y0/$u}] [expr {$x1/$u}] [expr {$y1/$u}]"
        foreach it [$i getITerms] {
            set n [$it getNet]; if {$n eq "NULL" || [$n isSpecial]} continue
            set r [$it getBBox]
            puts $fp "[$i getName] [expr {([$r xMin]+[$r xMax])/2.0/$u}] [expr {([$r yMin]+[$r yMax])/2.0/$u}]"
        }
        continue
    }
    set k "[expr {int((($x0+$x1)/2.0 - [$die xMin])/$bs)}] [expr {int((($y0+$y1)/2.0 - [$die yMin])/$bs)}]"
    set a [expr {($x1-$x0)/$u * ($y1-$y0)/$u}]
    if {[info exists A($k)]} { set A($k) [expr {$A($k)+$a}]; incr N($k) } else { set A($k) $a; set N($k) 1; set P($k) 0 }
    foreach it [$i getITerms] {
        set n [$it getNet]; if {$n eq "NULL" || [$n isSpecial]} continue
        set s [$n getSigType]; if {$s eq "POWER" || $s eq "GROUND"} continue
        incr P($k)
    }
}
foreach bt [$blk getBTerms] {
    set r [$bt getBBox]; if {[$r xMax] <= [$r xMin]} continue
    set s [[$bt getNet] getSigType]; if {$s eq "POWER" || $s eq "GROUND"} continue
    puts $fb "[$bt getName] [expr {([$r xMin]+[$r xMax])/2.0/$u}] [expr {([$r yMin]+[$r yMax])/2.0/$u}]"
}
set f [open $o/bins.txt w]
foreach k [array names A] { puts $f "$k [format %.2f $A($k)] $N($k) $P($k)" }
close $f; close $fm; close $fp; close $fb
puts "R25_DUMP bins [array size A] [expr {[clock seconds] - $t}] s"
exit
