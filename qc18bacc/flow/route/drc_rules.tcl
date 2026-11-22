# Kit min-step and end-of-line rules for the detailed router (R45 bug 1, results/r45.md; was impl/r45/lef57db45.tcl).
# The kit tech LEF (VERSION 5.6) holds its 65-nm metal rules as layer PROPERTYs
#   LEF57_MINSTEP "MINSTEP 0.09 MAXEDGES 1 ;"  and  LEF57_SPACING "SPACING .. ENDOFLINE .. WITHIN .. PARALLELEDGE .. ;"
# OpenROAD 2.0-12381 turns LEF57_MINSTEP into a LEF58 min-step rule that its detailed router does not check, and drops
# LEF57_SPACING (ODB-0388), so DRT never saw min-step (Calibre G.4) or end-of-line spacing (Calibre S.5).  qb_drc_rules
# writes both into the loaded tech as the classic rules DRT checks: dbTechLayer min step (+ max edges) and a V5.4 EOL
# spacing rule.  Routing layers only (a native cut-layer PARALLELOVERLAP changes pdngen via arrays: R45, 282 VIA6.R).
# Idempotent (a db saved after it already carries the rules).  Sourced by every script that runs detailed_route, after
# the tech is loaded and before detailed_route; the kit LEF is $::QC_PNR_LEF.
proc qb_drc_rules {} {
    set f [open $::QC_PNR_LEF]; set lef [read $f]; close $f
    set tech [ord::get_db_tech]; set u [$tech getDbUnitsPerMicron]; set nms 0; set neol 0
    foreach {all ln} [regexp -all -inline {\nLAYER (\S+)\s} $lef] {
        set i0 [string first "\nLAYER $ln\n" $lef]; if {$i0 < 0} { set i0 [string first "\nLAYER $ln " $lef] }
        set i1 [string first "\nEND $ln" $lef $i0]; set body [string range $lef $i0 $i1]
        if {![regexp {\n\s*TYPE\s+ROUTING} $body]} continue
        set l [$tech findLayer $ln]; if {$l eq "NULL"} continue
        if {[regexp {LEF57_MINSTEP "MINSTEP ([0-9.]+) MAXEDGES ([0-9]+)} $body -> len me] && [$l getMinStep] <= 0} {
            $l setMinStep [expr {round($len * $u)}]; $l setMinStepMaxEdges $me; incr nms
        }
        if {[regexp {LEF57_SPACING "SPACING ([0-9.]+) ENDOFLINE ([0-9.]+) WITHIN ([0-9.]+) PARALLELEDGE ([0-9.]+) WITHIN ([0-9.]+)} $body -> s w wi ps pw]} {
            set have 0
            foreach r [$l getV54SpacingRules] { if {[catch {$r getEol a b c d e g} e]} continue; if {$e} { set have 1 } }
            if {!$have} {
                set r [odb::dbTechLayerSpacingRule_create $l]
                $r setSpacing [expr {round($s * $u)}]
                $r setEol [expr {round($w * $u)}] [expr {round($wi * $u)}] 1 [expr {round($ps * $u)}] [expr {round($pw * $u)}] 0
                incr neol
            }
        }
    }
    puts "QB_DRC_RULES minstep rules added $nms, eol rules added $neol"
}
qb_drc_rules
