# PRE_PLACE_TCL of QC18-ACC: hard placement blockages over the thin row strips between the outer weight / param
# tiers and the core edge (QA_EDGE, needed so that pdngen's core grid covers the tiers: the core grid spans the row
# extent, deleting the rows brings back PDN-0232).  The strips only give global placement isolated low-capacity bins.
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set blk [ord::get_db_block]
set die [$blk getDieArea]
set ylo [expr {round($::QA_Y_BW * $u)}]; set yhi [expr {round($::QA_Y_TW_TOP * $u)}]
odb::dbBlockage_create $blk [$die xMin] [$die yMin] [$die xMax] $ylo
odb::dbBlockage_create $blk [$die xMin] $yhi [$die xMax] [$die yMax]
qc_log "rows_fix: placement blockages below [expr {$ylo / double($u)}] and above [expr {$yhi / double($u)}] um"
