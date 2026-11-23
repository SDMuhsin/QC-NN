# Fill-aware extraction of the routed block (R68), after the outputs step and the Calibre dummy metal fill of its GDS
# (blocks/<b>/run.sh fill: signoff/calibre/cal.sh fill -> DM.gds -> signoff/calibre/fill_def.py -> <run>/out/<top>_fill.def).
# The kit TLU+ (1p09m cworst / rcworst / typical / cbest / rcbest ITF headers) model metal-density thickness variation
# (DENSITY_POLYNOMIAL_ORDERS) but carry no FILL_* emulation, so the fill capacitance must come from the fill shapes
# themselves: the fill is read into the block label the outputs were written from (QB_ICC2_LABEL, out/label.txt) as DEF
# FILLS and extracted as floating metal (set_extraction_options -real_metalfill_extraction floating), then one SPEF per
# sign-off corner (site.tcl QC_SIGNOFF_CORNERS, with coupling: qb_timer SI) -> <run>/out/<top>_<c>_pt.spef.gz (gzip, R71:
# 9 x ~0.62 GB uncompressed kept the build host's /tmp near 90 %; PrimeTime reads it directly).  The block is
# not saved: the fill belongs to this layout only (an ECO round re-fills its own outputs).
#   (ICC2 extraction with the TLU+ of each corner: the kit has no StarRC nxtgrd for the 6X2Z stack)
source [file dirname [info script]]/common.tcl
open_lib $::QB_LIB
set label [qc_env QB_ICC2_LABEL route]
open_block $P(TOP)/$label
link_block
qb_timer
set o $::R/out/$P(TOP)
set def ${o}_fill.def
if {![file exists $def] || [file mtime $def] < [file mtime $o.gds]} { error "QB extract: fill DEF $def missing or older than $o.gds" }
read_def -include fills $def
set_extraction_options -real_metalfill_extraction floating
redirect $::R/rpt/extract_options.rpt { report_extraction_options }
qb_line "extract label $label fill DEF [file tail $def] shapes [exec grep -c {^- LAYER } $def], real_metalfill_extraction floating"
update_timing -full
file delete {*}[glob -nocomplain $o.*.spef ${o}_*_pt.spef ${o}_*_pt.spef.gz]
write_parasitics -output $o
# write_parasitics names each file after its parasitic tech and temperature (<o>.<tluplus>_<T>.spef) and lists the
# scenarios of every file in <o>.spef_scenario ("<file> for scenarios:" then "scenario: func_<c>, ..." lines)
set map [exec cat $o.spef_scenario]
foreach l [split $map "\n"] {
    if {[regexp {^(\S+\.spef) for scenarios:} $l -> f]} { continue }
    if {[regexp {scenario:\s*func_(\S+?),} $l -> c] && [info exists f]} { set spef($c) $f }
}
foreach c $::QC_SIGNOFF_CORNERS {
    if {![info exists spef($c)] || ![file exists $spef($c)]} { error "QB extract: no SPEF for corner $c in $o.spef_scenario" }
    incr users($spef($c))
}
# one <o>_<c>_pt.spef.gz per corner (a file shared by corners is compressed for each, then deleted after its last one)
foreach c $::QC_SIGNOFF_CORNERS {
    set f $spef($c)
    exec pigz -p [qc_env QB_ICC2_CORES 16] -c $f > ${o}_${c}_pt.spef.gz
    if {![incr users($f) -1]} { file delete $f }
    qb_line "extract spef $c [file tail $f] [file size ${o}_${c}_pt.spef.gz] (gz)"
}
qb_qor extract
puts "QB_ICC2_DONE extract"
