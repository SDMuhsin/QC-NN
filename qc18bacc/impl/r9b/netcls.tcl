# R9b: net -> traffic class of its root driver (repair / CTS buffers walked back), for ovf9.py.  QB_DB [grt].
# Classes: MACRO:<type>, PORT:<bus>, glue (u_top_* comb), reg:<base> (u_top_* flops), prm, head, pcol, clock, rsz?, other.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env QB_DB grt].odb
proc isbuf {i} { return [regexp {^(BUFF|INV|CKBD|CKND|DEL)} [[$i getMaster] getName]] }
proc root {net d} {
    foreach bt [$net getBTerms] { if {[$bt getIoType] eq "INPUT"} { return [list PORT [$bt getName]] } }
    foreach it [$net getITerms] {
        if {![$it isOutputSignal]} continue
        set i [$it getInst]
        if {[isbuf $i] && $d < 40} {
            foreach x [$i getITerms] { if {[$x isInputSignal] && [$x getNet] ne "NULL"} { return [root [$x getNet] [expr {$d + 1}]] } }
        }
        return [list INST $i]
    }
    return [list NONE ""]
}
set fo [open $::OUT/rpt/netcls.txt w]
foreach net [[ord::get_db_block] getNets] {
    set st [$net getSigType]
    if {$st eq "POWER" || $st eq "GROUND"} continue
    if {$st eq "CLOCK" || [string match clknet* [$net getName]]} { puts $fo "[$net getName] clock"; continue }
    lassign [root $net 0] k o
    if {$k eq "PORT"} { set c "PORT:[regsub {(_\d+_|\[\d+\]|_\d+)$} [regsub {_c\d+$} $o {}] {}]" } elseif {$k eq "NONE"} { set c none } else {
        set m [$o getMaster]; set n [$o getName]
        if {[$m isBlock]} { set c "MACRO:[$m getName]" } elseif {[string match u_top_g_r3b_u_prm* $n]} { set c prm
        } elseif {[string match u_head/g_pcol* $n]} { set c pcol } elseif {[string match u_head* $n]} { set c head
        } elseif {[regexp {^(DF|EDF|SDF|LH|CKLN)} [$m getName]]} { set c "reg:[regsub -all {\d+} [regsub {_reg.*} $n {}] N]"
        } elseif {[string match u_top_* $n]} { set c glue } else { set c "other:[regsub -all {\d+} [lindex [split $n /] 0] N]" }
    }
    puts $fo "[$net getName] $c"
}
close $fo
puts "R9B netcls done"
exit
