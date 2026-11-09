# FLOORPLAN_TCL of QC18-ACC: remove the standard-cell rows of the thin strips between the outer weight / param tiers
# and the core edge (QA_EDGE, needed for pdngen; ~5 rows each, far from all logic).  They only give global placement
# isolated low-capacity bins.
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set ylo [expr {round($::QA_Y_BW * $u)}]; set yhi [expr {round($::QA_Y_TW_TOP * $u)}]
set n 0
foreach r [[ord::get_db_block] getRows] {
    set bb [$r getBBox]
    if {[$bb yMax] <= $ylo || [$bb yMin] >= $yhi} { odb::dbRow_destroy $r; incr n }
}
qc_log "rows_fix: removed $n rows outside y [expr {$ylo / double($u)}] .. [expr {$yhi / double($u)}] um"
