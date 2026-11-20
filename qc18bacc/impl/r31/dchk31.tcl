# R31: for every pin of R31_PINS (file of inst/pin, e.g. <run>/r31_seed.txt) in db R31_DB [route_dr]: its net, the
# number of ANTENNA (diode) cells on that net, the driver, and the net's routed layers.  impl/r29/or29.sh <tag> dchk31.tcl <log>
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/[qc_env R31_DB route_dr].odb
set blk [ord::get_db_block]
set f [open $::env(R31_PINS)]
while {[gets $f l] >= 0} {
    set i [string last / $l]; set in [string range $l 0 [expr {$i - 1}]]; set pn [string range $l [expr {$i + 1}] end]
    set inst [$blk findInst $in]; if {$inst eq "NULL"} { puts "R31DCHK $l no_inst"; continue }
    set it [$inst findITerm $pn]; if {$it eq "NULL"} { puts "R31DCHK $l no_pin"; continue }
    set n [$it getNet]; set nd 0; set drv -
    foreach x [$n getITerms] {
        set m [[$x getInst] getMaster]
        if {[string match ANTENNA* [$m getName]]} { incr nd }
        if {[$x isOutputSignal]} { set drv "[[$x getInst] getName]([$m getName])" }
    }
    puts "R31DCHK $l net [$n getName] diodes $nd sinks [llength [$n getITerms]] driver $drv master [[$inst getMaster] getName]"
}
exit
