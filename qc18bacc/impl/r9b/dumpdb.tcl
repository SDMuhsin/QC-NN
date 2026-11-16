# R9b: pin-level connectivity dump of a checkpoint (QB_DB, default grt) for cone.py: I <inst> <master> <seq|comb|macro>,
# N <net> <driver inst:pin|PORT:name|-> <sink ...>
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env QB_DB grt].odb
set f [open $::OUT/rpt/dumpdb.txt w]
foreach i [[ord::get_db_block] getInsts] {
    set m [$i getMaster]; set n [$m getName]
    set k [expr {[$m isBlock] ? "macro" : ([regexp {^(DF|EDF|SDF|LH|LN|CKLN)} $n] ? "seq" : "comb")}]
    puts $f "I [$i getName] $n $k"
}
foreach net [[ord::get_db_block] getNets] {
    set st [$net getSigType]; if {$st eq "POWER" || $st eq "GROUND"} continue
    set d -; set s {}
    foreach it [$net getITerms] {
        set t "[[$it getInst] getName]:[[$it getMTerm] getName]"
        if {[$it isOutputSignal]} { set d $t } elseif {[$it isInputSignal]} { lappend s $t }
    }
    foreach bt [$net getBTerms] { if {[$bt getIoType] eq "INPUT"} { set d PORT:[$bt getName] } else { lappend s PORT:[$bt getName] } }
    puts $f "N [$net getName] $d [join $s { }]"
}
close $f
puts "R9B dumpdb done"
exit
