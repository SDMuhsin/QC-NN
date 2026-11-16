# R9b: unplaced connectivity dump of a DC chip netlist for impl/r6a/cuts.py (format of impl/r6a/net_dump.tcl).
# env: QB_NETLIST (.v), QB_TOP [qb_chip], QB_OUT (dump file), QC_PNR_OUT (scratch dir), QB_BLK, QB_MDIR as impl/r5b/chip.cfg
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set ::QC_CORNERS tt
set ::QC_PNR_MAX_LAYER M9
set P(TOP) [qc_env QB_TOP qb_chip]
set P(NETLIST) $::env(QB_NETLIST)
set P(SDC) none
set _blk [qc_env QB_BLK $::env(QC_BUILD)/r5b_blk]
set _mdir [qc_env QB_MDIR /tmp/$::env(USER)/qcnn/macros]
set P(MACRO_LEFS) [list $_blk/qb_col_blk_ring.lef]
set P(MACRO_LIBS_tt) [list $_blk/qb_col_blk_tt_ins.lib]
foreach m {qb_w_204x144m2 qb_s_256x128m1 qb_b_128x128m1 qb_i_128x128m1 qb_p_240x144m2 qb_d_624x80m8 qb_f_3232x128m8} {
    lappend P(MACRO_LEFS) $_mdir/$m/$m.lef
    lappend P(MACRO_LIBS_tt) $_mdir/$m/${m}_tt_1p0v_25c_syn.lib
}
qc_config
qc_read_libs
qc_read_design
set blk [ord::get_db_block]
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set fo [open $::env(QB_OUT) w]
foreach i [$blk getInsts] {
    set m [$i getMaster]
    puts $fo "I [$i getName] [$m getName] [format %.3f [expr {[$m getWidth] / $u * [$m getHeight] / $u}]] 0 0"
}
foreach net [$blk getNets] {
    set st [$net getSigType]; if {$st eq "POWER" || $st eq "GROUND"} continue
    set d ""; set s {}
    foreach it [$net getITerms] {
        set i [$it getInst]; set t [$i getName]
        if {[[$i getMaster] isBlock] || [qc_env QB_PINS 0]} { set t "$t:[[$it getMTerm] getName]@N" }
        if {[$it isOutputSignal]} { set d $t } elseif {[$it isInputSignal]} { lappend s $t }
    }
    foreach bt [$net getBTerms] {
        if {[$bt getIoType] eq "INPUT"} { set d PORT:[$bt getName] } else { lappend s PORT:[$bt getName] }
    }
    if {$d eq ""} { set d - }
    puts $fo "N [$net getName] $d [join $s { }]"
}
close $fo
puts "R9B_DUMP done [llength [$blk getInsts]] insts"
exit
