# R18 (results/r18.md): net / cell class dump of a qb_act2_blk db for cuts.py / geo.py / ovf9.py.  Read only.
#   QB_DB [cts_rt] of $QC_PNR_OUT/db; QB18_OUT dir ->
#   nets.txt:  <net> <root cat> <root inst> <n leaf sinks> <cat:n,...>   root = driver walked back through buffers / inverters,
#              leaf sinks = loads walked forward through buffers / inverters (repair / DC buffers inherit their net's class)
#   cells.txt: <cat> <xc> <yc> <w> <h> <tag> <inst> <out net>   tag: lbff c.s.b (ctx, slot, bit), pm c.s (from its fan-in lb flop),
#              s1ff / s1c / s2ff / s2c row (S1 reg i -> row i / 256, act reg i -> row i / 288; comb cells: row of the first reg
#              reached forward), else -
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/[qc_env QB_DB cts_rt].odb
set od [qc_env QB18_OUT $::OUT/rpt]
set blk [ord::get_db_block]
set ::u [expr {double([$blk getDbUnitsPerMicron])}]
proc isbuf {i} { return [regexp {^(BUFF|INV|CKBD|CKND|DEL)} [[$i getMaster] getName]] }
proc cat {i} {
    if {[info exists ::CAT($i)]} { return $::CAT($i) }
    set n [$i getName]; set m [[$i getMaster] getName]
    if {[string match clkbuf_* $n] || [regexp {^CKLN} $m]} { set c clk
    } elseif {[regexp {/u_lb/lb_reg_} $n]} { set c lbff
    } elseif {[string match */u_lb/* $n]} { set c lbc
    } elseif {[string match */g_pmr_* $n]} { set c pm
    } elseif {[regexp {/u_s1/s1_reg_} $n]} { set c s1ff
    } elseif {[string match */u_s1/* $n]} { set c s1c
    } elseif {[regexp {/u_s2/act_reg_} $n]} { set c s2ff
    } elseif {[string match */u_s2/* $n]} { set c s2c
    } elseif {[regexp {/(sdq|rdq)_reg_} $n]} { set c wdq
    } elseif {[regexp {/s1c_r_reg} $n]} { set c sel:s1c
    } elseif {[regexp {/sel1[ab]_reg} $n]} { set c sel:sel1
    } elseif {[regexp {/sel2(_1)?_reg} $n]} { set c sel:sel2
    } elseif {[regexp {/shq_reg} $n]} { set c sel:shq
    } elseif {[regexp {/wer_reg} $n]} { set c sel:wer
    } elseif {[regexp {g_pipe_\d+__u_ap/q_reg} $n]} { set c apipe
    } elseif {[regexp {^u_dist/q_reg} $n]} { set c dist
    } elseif {[isbuf $i]} { set c buf
    } elseif {[regexp {^(DF|EDF|SDF|LH|LN)} $m]} { set c ff
    } else { set c comb }
    set ::CAT($i) $c; return $c
}
proc onet {i} { foreach it [$i getITerms] { if {[$it isOutputSignal] && [$it getNet] ne "NULL"} { return [$it getNet] } }; return NULL }
proc root {net d} {
    foreach bt [$net getBTerms] { if {[$bt getIoType] eq "INPUT"} { return [list port [$bt getName]] } }
    foreach it [$net getITerms] {
        if {![$it isOutputSignal]} continue
        set i [$it getInst]
        if {[isbuf $i] && [cat $i] eq "buf" && $d < 40} {
            foreach x [$i getITerms] { if {[$x isInputSignal] && [$x getNet] ne "NULL"} { return [root [$x getNet] [expr {$d + 1}]] } }
        }
        return [list [cat $i] [$i getName]]
    }
    return [list none -]
}
proc leaves {net d arr} {
    upvar $arr L
    foreach bt [$net getBTerms] { if {[$bt getIoType] eq "OUTPUT"} { incr L(port) } }
    foreach it [$net getITerms] {
        if {![$it isInputSignal]} continue
        set i [$it getInst]; set c [cat $i]
        if {$c eq "buf" && $d < 40} { set o [onet $i]; if {$o ne "NULL"} { leaves $o [expr {$d + 1}] L; continue } }
        incr L($c)
    }
}
set f [open $od/nets.txt w]
set nn 0
foreach net [$blk getNets] {
    set st [$net getSigType]
    if {$st eq "POWER" || $st eq "GROUND"} continue
    if {$st eq "CLOCK" || [string match clknet* [$net getName]]} { puts $f "[$net getName] clock - 0 -"; continue }
    lassign [root $net 0] rc rn
    array unset L; array set L {}
    leaves $net 0 L
    set s {}; set t 0
    foreach k [lsort [array names L]] { lappend s "$k:$L($k)"; incr t $L($k) }
    if {![llength $s]} { set s - }
    puts $f "[$net getName] $rc $rn $t [join $s ,]"
    incr nn
}
close $f
puts "R18_NETS $nn"
# rows / slots
proc fwdrow {i want d} {
    if {[info exists ::ROW($i)]} { return $::ROW($i) }
    set r -1
    set o [onet $i]
    if {$o ne "NULL" && $d < 16} {
        foreach it [$o getITerms] {
            if {![$it isInputSignal]} continue
            set j [$it getInst]; set c [cat $j]
            if {$c eq $want} { set r [rowof $j]; break }
        }
        if {$r < 0} {
            foreach it [$o getITerms] {
                if {![$it isInputSignal]} continue
                set j [$it getInst]; set c [cat $j]
                if {$c eq [string map {ff c} $want] || $c eq "buf"} { set r [fwdrow $j $want [expr {$d + 1}]]; if {$r >= 0} break }
            }
        }
    }
    set ::ROW($i) $r; return $r
}
proc rowof {j} {
    if {[regexp {s1_reg_(\d+)_} [$j getName] -> k]} { return [expr {$k / 256}] }
    if {[regexp {act_reg_(\d+)_} [$j getName] -> k]} { return [expr {$k / 288}] }
    return -1
}
set f [open $od/cells.txt w]
foreach i [$blk getInsts] {
    set c [cat $i]; set m [$i getMaster]
    if {[regexp {^(FILL|DCAP|TAP|GFILL|TIE)} [$m getName]]} continue
    set b [$i getBBox]; set tag -; set n [$i getName]
    switch $c {
        lbff { if {[regexp {g_ctx_(\d+)__u_ctx/u_lb/lb_reg_(\d+)__(\d+)_} $n -> cc s k]} { set tag $cc.$s.$k } }
        pm   { foreach it [$i getITerms] { if {[$it isInputSignal] && [$it getNet] ne "NULL"} {
                   lassign [root [$it getNet] 0] rc rn
                   if {$rc eq "lbff" && [regexp {g_ctx_(\d+)__u_ctx/u_lb/lb_reg_(\d+)__(\d+)_} $rn -> cc s k]} { set tag $s.$k; break } } } }
        s1ff - s2ff { set tag [rowof $i] }
        s1c  { set tag [fwdrow $i s1ff 0] }
        s2c  { set tag [fwdrow $i s2ff 0] }
    }
    set o [onet $i]; set on [expr {$o eq "NULL" ? "-" : [$o getName]}]
    puts $f [format "%s %.2f %.2f %.2f %.2f %s %s %s" $c [expr {([$b xMin] + [$b xMax]) / 2 / $::u}] [expr {([$b yMin] + [$b yMax]) / 2 / $::u}] \
        [expr {([$b xMax] - [$b xMin]) / $::u}] [expr {([$b yMax] - [$b yMin]) / $::u}] $tag $n $on]
}
close $f
set f [open $od/die.txt w]; set d [$blk getDieArea]; set c [$blk getCoreArea]
puts $f "die [expr {[$d xMax] / $::u}] [expr {[$d yMax] / $::u}] core [expr {[$c xMin] / $::u}] [expr {[$c yMin] / $::u}] [expr {[$c xMax] / $::u}] [expr {[$c yMax] / $::u}]"
foreach bt [$blk getBTerms] { set bb [$bt getBBox]; puts $f "P [$bt getName] [expr {[$bb xMin] / $::u}] [expr {[$bb yMin] / $::u}]" }
close $f
puts "R18_DUMP done"
exit
