# R13 (results/r13.md): dump of a placed / routed qb_act2_blk db for the M2-short analysis (m2_short.py):
#   one line per instance: master llx lly urx ury (um) n_signal_pins name
# Env: QB13_DB (odb), QB13_OUT (text file).  openroad -no_init -exit cell_dump.tcl
read_db $::env(QB13_DB)
set blk [ord::get_db_block]
set dbu [$blk getDbUnitsPerMicron]
set f [open $::env(QB13_OUT) w]
foreach i [$blk getInsts] {
    set n 0
    foreach it [$i getITerms] {
        set nt [$it getNet]
        if {$nt ne "NULL" && [$nt getSigType] eq "SIGNAL"} { incr n }
    }
    set b [$i getBBox]
    puts $f [format "%s %.2f %.2f %.2f %.2f %d %s" [[$i getMaster] getName] [expr {[$b xMin] / double($dbu)}] [expr {[$b yMin] / double($dbu)}] \
        [expr {[$b xMax] / double($dbu)}] [expr {[$b yMax] / double($dbu)}] $n [$i getName]]
}
close $f
puts "QB13_DUMP [llength [$blk getInsts]] insts"
