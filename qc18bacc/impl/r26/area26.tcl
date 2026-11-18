# R26 (results/r26.md): std-cell census of db/$QB_DB.odb -> $QC_PNR_OUT/r26/inst_$QB_DB.txt
#   "<inst> <master> <area um2> <signal pins>" for every non-block instance (pins = ITerms on non-supply nets, as
#   impl/r25/dump25.tcl), then R26_STD totals.  rep26.py compares two dumps (added / removed / resized by prefix).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set db [qc_env QB_DB cts_rt]
read_db $::OUT/db/$db.odb
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
file mkdir $::OUT/r26
set f [open $::OUT/r26/inst_$db.txt w]
set n 0; set a 0.0; set np 0
foreach i [[ord::get_db_block] getInsts] {
    set m [$i getMaster]
    if {[$m getType] ne "CORE" && ![string match "CORE_*" [$m getType]]} { continue }
    set ar [expr {[$m getWidth] * [$m getHeight] / $u / $u}]
    set p 0
    foreach it [$i getITerms] { set nt [$it getNet]; if {$nt ne "NULL" && ![$nt isSpecial] && [$nt getSigType] ni {POWER GROUND}} { incr p } }
    puts $f [format "%s %s %.4f %d" [$i getName] [$m getName] $ar $p]
    incr n; set a [expr {$a + $ar}]; incr np $p
}
close $f
puts [format "R26_STD %s inst %d area_um2 %.0f sig_pins %d" $db $n $a $np]
exit
