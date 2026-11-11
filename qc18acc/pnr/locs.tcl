# Diagnostic (results/pnr_v4.md section 2): dump "name x y" (um, cell origin) of the standard cells matching QA_RE in
# db/QA_STEP.odb to QA_OUTF (then locs.py: centroids of the crossbar register groups / PE rows).
#   QC_PNR_OUT=<run dir> QA_STEP=place QA_OUTF=<file> QA_RE=<regexp> openroad -exit locs.tcl
read_db $::env(QC_PNR_OUT)/db/$::env(QA_STEP).odb
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set f [open $::env(QA_OUTF) w]
foreach i [[ord::get_db_block] getInsts] {
    if {[[$i getMaster] isBlock]} { continue }
    set nm [$i getName]
    if {[regexp $::env(QA_RE) $nm]} { set b [$i getBBox]; puts $f "$nm [expr {[$b xMin]/double($u)}] [expr {[$b yMin]/double($u)}]" }
}
close $f
