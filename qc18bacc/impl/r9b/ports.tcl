# R9b: per hub port, whether it is registered on the hub side (through buffers / inverters only):
#   input:  every sink is a flop D-side pin / macro input / ICG;   output: the driver is a flop Q / macro output.
# env QB_NETLIST (qb_hub.v), QB_OUT; libs as dump.tcl.  Lines: <port> <in|out> <reg 0|1> <first endpoint master/pin>
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set ::QC_CORNERS tt
set P(TOP) qb_hub
set P(NETLIST) $::env(QB_NETLIST)
set P(SDC) none
set _mdir [qc_env QB_MDIR /tmp/$::env(USER)/qcnn/macros]
set P(MACRO_LEFS) {}; set P(MACRO_LIBS_tt) {}
foreach m {qb_s_256x128m1 qb_b_128x128m1 qb_i_128x128m1 qb_p_240x144m2 qb_f_3232x128m8} {
    lappend P(MACRO_LEFS) $_mdir/$m/$m.lef
    lappend P(MACRO_LIBS_tt) $_mdir/$m/${m}_tt_1p0v_25c_syn.lib
}
qc_config
qc_read_libs
qc_read_design
proc isbuf {m} { return [regexp {^(BUFF|INV|CKBD|CKND|DEL)} [$m getName]] }
proc isseq {m} { return [expr {[$m isBlock] || [regexp {^(DF|EDF|SDF|SEDF|LH|LN|CKLN|DFK|DFN|DFX|DFS|DFC)} [$m getName]]}] }
# forward: all non-buffer sinks of net; backward: the non-buffer driver
proc sinks {net {d 0}} {
    set r {}
    foreach it [$net getITerms] {
        if {![$it isInputSignal]} continue
        set i [$it getInst]; set m [$i getMaster]
        if {[isbuf $m] && $d < 20} {
            foreach o [$i getITerms] { if {[$o isOutputSignal] && [$o getNet] ne "NULL"} { lappend r {*}[sinks [$o getNet] [expr {$d + 1}]] } }
        } else { lappend r $it }
    }
    return $r
}
proc driver {net {d 0}} {
    foreach it [$net getITerms] {
        if {![$it isOutputSignal]} continue
        set i [$it getInst]; set m [$i getMaster]
        if {[isbuf $m] && $d < 20} {
            foreach x [$i getITerms] { if {[$x isInputSignal] && [$x getNet] ne "NULL"} { return [driver [$x getNet] [expr {$d + 1}]] } }
        }
        return $it
    }
    return ""
}
set fo [open $::env(QB_OUT) w]
foreach bt [[ord::get_db_block] getBTerms] {
    set net [$bt getNet]; set dir [expr {[$bt getIoType] eq "INPUT" ? "in" : "out"}]
    if {$net eq "NULL"} { puts $fo "[$bt getName] $dir - unconnected"; continue }
    if {$dir eq "in"} {
        set ss [sinks $net]; set reg [expr {[llength $ss] > 0}]; set ex -
        foreach it $ss {
            set m [[$it getInst] getMaster]; set pn [[$it getMTerm] getName]
            if {!([$m isBlock] || ([isseq $m] && ![string match CP* $pn]))} { set reg 0; set ex "[$m getName]/$pn"; break }
        }
        if {$reg && [llength $ss]} { set it [lindex $ss 0]; set ex "[[[$it getInst] getMaster] getName]/[[$it getMTerm] getName]" }
        puts $fo "[$bt getName] in $reg $ex [llength $ss]"
    } else {
        set it [driver $net]
        if {$it eq ""} { puts $fo "[$bt getName] out 0 none 0"; continue }
        set m [[$it getInst] getMaster]
        puts $fo "[$bt getName] out [isseq $m] [$m getName]/[[$it getMTerm] getName] 1"
    }
}
close $fo
puts "R9B_PORTS done"
exit
