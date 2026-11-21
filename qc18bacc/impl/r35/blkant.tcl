# R35 (results/r35a.md bug 10): per block port, the antenna data a top-level check needs: ANTENNAGATEAREA = gate area of
# the std-cell inputs on the port net inside the block, ANTENNADIFFAREA = diffusion area of its drivers (cell LEF
# antenna models).  db/<QB35_ADB [finish]> -> $QB35_AOUT lines "port master pin in|out" (impl/r35/blkant.py sums the cell LEF areas, patches a LEF).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env QB35_ADB finish].odb
set f [open $::env(QB35_AOUT) w]; set n 0
foreach b [[ord::get_db_block] getBTerms] {
    if {[$b getSigType] ne "SIGNAL" && [$b getSigType] ne "CLOCK"} continue
    set net [$b getNet]; if {$net eq "NULL"} continue
    foreach it [$net getITerms] {
        puts $f [format "%s %s %s %s" [$b getName] [[[$it getInst] getMaster] getName] [[$it getMTerm] getName] [expr {[$it isInputSignal] ? "in" : ([$it isOutputSignal] ? "out" : "x")}]]
    }
    incr n
}
close $f; puts "R35_BLKANT ports $n"
exit
