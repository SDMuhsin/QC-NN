# R46 probe (read_db only): tech vias the global router uses as default vias (grt::GlobalRouter::getDefaultVias:
# OR_DEFAULT property, else the first via per bottom routing level) and whether each has a bbox / boxes.
# repair_antennas encodes these into temporary dbWires; odb::dbWirePathItr::getNextShape (TECH_VIA) calls
# via->getBBox()->getBox() with no null check.  Usage: openroad -exit via46.tcl with R46_DB=<odb path>.
read_db $::env(R46_DB)
set tech [[ord::get_db] getTech]
set n 0; set dflt {}
foreach v [$tech getVias] {
    set p [odb::dbStringProperty_find $v OR_DEFAULT]
    set bb [$v getBBox]; set nb [llength [$v getBoxes]]
    set bl [$v getBottomLayer]; set tl [$v getTopLayer]
    set lv [expr {$bl eq "NULL" ? "-" : [$bl getRoutingLevel]}]
    set line [format "R46_VIA %-28s bot %-4s lvl %-2s top %-4s default %d boxes %d bbox %s rule %s" [$v getName] \
        [expr {$bl eq "NULL" ? "NULL" : [$bl getName]}] $lv [expr {$tl eq "NULL" ? "NULL" : [$tl getName]}] \
        [expr {$p ne "NULL"}] $nb [expr {$bb eq "NULL" ? "NULL" : [list [$bb xMin] [$bb yMin] [$bb xMax] [$bb yMax]]}] \
        [expr {[$v getViaGenerateRule] eq "NULL" ? "-" : [[$v getViaGenerateRule] getName]}]]
    set first [expr {$lv ne "-" && ![info exists seen($lv)]}]
    if {$first} { set seen($lv) 1 }
    set tlv [expr {$tl eq "NULL" ? "-" : [$tl getRoutingLevel]}]
    if {$p ne "NULL" || $bb eq "NULL" || $first || $lv eq "-" || $tlv eq "-" || $tlv != $lv + 1} { puts "$line first $first" }
    incr n
}
puts "R46_VIA total $n"
