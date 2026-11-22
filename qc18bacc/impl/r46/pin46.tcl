# R46 probe (read_db only): pins of net R46_NET (all shapes on layer R46_LAYER [M1]) whose bbox meets the GRT gcells in
# R46_GC ("x_dbu y_dbu ..." gcell centres; gcell size R46_GSZ [6000] dbu) -> which pin a GRT segment end lands on.
# Usage: R46_DB=<odb> R46_NET=<net> R46_GC="117000 6363000 123000 6363000" openroad -exit pin46.tcl
read_db $::env(R46_DB)
set b [ord::get_db_block]
set net [$b findNet $::env(R46_NET)]
set ly [expr {[info exists ::env(R46_LAYER)] ? $::env(R46_LAYER) : "M1"}]
set h [expr {([info exists ::env(R46_GSZ)] ? $::env(R46_GSZ) : 6000) / 2}]
puts "R46_PIN net [$net getName] iterms [llength [$net getITerms]] bterms [llength [$net getBTerms]]"
foreach it [$net getITerms] {
    set inst [$it getInst]; set mt [$it getMTerm]
    set t [$inst getTransform]
    set lys {}
    foreach mp [$mt getMPins] { foreach g [$mp getGeometry] { set l [$g getTechLayer]; if {$l ne "NULL" && [$l getName] ni $lys} { lappend lys [$l getName] } } }
    # pin bbox (all its shapes, placed) against the gcells; only pins whose shapes are all on R46_LAYER count
    set bb [$it getBBox]; set hit {}
    if {$lys eq [list $ly]} { foreach {cx cy} $::env(R46_GC) {
        if {[$bb xMax] >= $cx - $h && [$bb xMin] <= $cx + $h && [$bb yMax] >= $cy - $h && [$bb yMin] <= $cy + $h} { lappend hit "gcell($cx,$cy)" } } }
    puts "R46_PIN [$inst getName]/[$mt getName] ([[$inst getMaster] getName]) bbox [$bb xMin] [$bb yMin] [$bb xMax] [$bb yMax] layers $lys [expr {[llength $hit] ? "ON $hit" : ""}]"
}
