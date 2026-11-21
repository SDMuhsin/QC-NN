# R45 probe: what OpenROAD's db tech holds for M1/M2 after read_lef <lef> (env R45_LEF): min-step, EOL spacing, min-cut
read_lef $::env(R45_LEF)
set tech [ord::get_db_tech]
foreach ln {M1 M2 M3} {
    set l [$tech findLayer $ln]
    puts "R45 $ln minstep [$l getMinStep] maxedges [expr {[catch {$l getMinStepMaxEdges} e] ? "n/a($e)" : $e}] lef58minstep [llength [$l getTechLayerMinStepRules]]"
    set eol 0
    puts "R45 $ln v54 spacing rules [llength [$l getV54SpacingRules]] eol $eol lef58eol [llength [$l getTechLayerSpacingEolRules]] mincut [llength [$l getMinCutRules]]"
}
if {[info exists ::env(R45_FIXPROBE)]} {
    set ::QC_PNR_LEF $::env(R45_LEF); source $::env(R45_FIXPROBE)
    foreach ln {M1 M2} { set l [$tech findLayer $ln]; puts "R45 after-fix $ln minstep [$l getMinStep] maxedges [$l getMinStepMaxEdges] v54 [llength [$l getV54SpacingRules]]" }
}
