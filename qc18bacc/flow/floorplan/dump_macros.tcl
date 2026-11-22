# impl/r5b/run.sh: list the block / macro instances of db/init.odb (name master width height, um) -> macros.txt
read_db $::env(QB_RUN)/db/init.odb
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set f [open $::env(QB_RUN)/macros.txt w]
foreach i [[ord::get_db_block] getInsts] {
    set m [$i getMaster]
    if {![$m isBlock]} { continue }
    puts $f "[$i getName] [$m getName] [expr {[$m getWidth] / double($u)}] [expr {[$m getHeight] / double($u)}]"
}
close $f
exit
