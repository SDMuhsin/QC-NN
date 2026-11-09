# PrimeTime PX: power breakdown INSIDE the PE array (v2 netlist, whose qa_pe has function sub-instances), averaged
# over the 64 PEs (driven by qc18acc/power/power.sh -e; same setup as pt_power.tcl: tt, synthesis WLM, ideal clock,
# synthesis SDC at QC_PERIOD, SAIF of the GLS run).
# Method: every leaf cell of every u_array/*u_pe hierarchy is assigned to one group by its hierarchy / name, with
# PT's per-cell power (total = internal + switching of the cell's output nets + leakage):
#   rot      cells under u_rot1, u_rot2 (qa_pe_rot: rotator muxes)
#   tadd     cells under u_tadd (qa_pe_tadd: trit negate / zero + 2-term add)
#   accadd   cells under u_acc (qa_pe_acc: accumulate add incl. the first-step zeroing)
#   accreg   acc_q_reg* registers (data part: internal power without the clock pin, Q-net switching, leakage)
#   shreg    sh_out_reg* registers (data part) + every other leaf cell at the PE top level (the capture / shift-in
#            muxes of the shadow chain = drain path)
#   clock    the DC clock gates (clk_gate_* hierarchies: CKLNQD, incl. the gated-clock net switching) + the clock-pin
#            internal power of all PE registers (PT power group clock_network, per cell: report_power -cell_power
#            -groups clock_network), which is moved out of accreg / shreg
# Check: the groups sum to the PE hierarchy power (total_power attribute of the 64 hierarchical cells).
# Output: ${OUT}_pe.txt (per-PE average W per group, and the same for internal / switching / leakage).
source $::env(QC_FLOW)/common/lib.tcl
set top qa_top
set corner tt
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs $corner]]
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
set_app_var power_default_toggle_rate 0
read_verilog $::env(SYN)/$top.v
current_design $top
link_design
set ::env(QC_CORNER) $corner
qc_apply_constraints $corner
set wlm [qc_wire_load $corner]
read_saif -strip_path qa_tb/dut $::env(SAIF)
update_power
set o $::env(OUT)

set pes [get_cells -filter "is_hierarchical==true" u_array/*u_pe]
set npe [sizeof_collection $pes]
array set G {}
foreach g {rot tadd accadd accreg shreg clock} { foreach k {int sw leak tot} { set G($g,$k) 0.0 } }
proc acc {g c} {
    global G
    foreach a {internal_power switching_power leakage_power total_power} k {int sw leak tot} {
        if {[catch {set x [get_attribute $c $a]}] || $x eq ""} { set x 0.0 }
        set G($g,$k) [expr {$G($g,$k) + $x}]
    }
}
set pe_tot 0.0
foreach_in_collection pe $pes {
    set pn [get_object_name $pe]
    set pe_tot [expr {$pe_tot + [get_attribute $pe total_power]}]
    current_instance $pn
    set leaves [get_cells -hierarchical -filter "is_hierarchical==false"]
    current_instance
    foreach_in_collection c $leaves {
        set n [string range [get_attribute $c full_name] [expr {[string length $pn] + 1}] end]
        if {[string match u_rot* $n]} { set g rot } elseif {[string match u_tadd/* $n]} { set g tadd } \
        elseif {[string match u_acc/* $n]} { set g accadd } elseif {[string match clk_gate_* $n]} { set g clock } \
        elseif {[string match acc_q_reg* $n]} { set g accreg } else { set g shreg }
        acc $g $c
    }
}
# clock-pin internal power of the PE registers (clock_network group), moved from accreg / shreg to clock
current_instance u_array
set regs [get_cells -hierarchical -filter "is_hierarchical==false && is_sequential==true && full_name=~*u_pe/*"]
current_instance
redirect -variable rp { report_power -nosplit -cell_power -groups clock_network $regs }
set ck(accreg) 0.0; set ck(shreg) 0.0; set nck 0
foreach l [split $rp "\n"] {
    if {[regexp {^\S*u_pe/(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $l -> n i s k t] && [string is double $i]} {
        if {[string match clk_gate_* $n]} { continue }
        set g [expr {[string match acc_q_reg* $n] ? "accreg" : "shreg"}]
        set ck($g) [expr {$ck($g) + $i}]
        incr nck
    }
}
foreach g {accreg shreg} {
    set G($g,int) [expr {$G($g,int) - $ck($g)}]; set G($g,tot) [expr {$G($g,tot) - $ck($g)}]
    set G(clock,int) [expr {$G(clock,int) + $ck($g)}]; set G(clock,tot) [expr {$G(clock,tot) + $ck($g)}]
}
set fh [open ${o}_pe.txt w]
puts $fh "# per-PE average over $npe PEs, W (period_ns $::env(QC_PERIOD), wire_load $wlm); register clock pins: $nck cells"
puts $fh "# group internal_W switching_W leakage_W total_W"
set s 0.0
foreach g {rot tadd accadd accreg shreg clock} {
    puts $fh [format "pe:%s %.6e %.6e %.6e %.6e" $g [expr {$G($g,int)/$npe}] [expr {$G($g,sw)/$npe}] \
        [expr {$G($g,leak)/$npe}] [expr {$G($g,tot)/$npe}]]
    set s [expr {$s + $G($g,tot)}]
}
puts $fh [format "pe:sum_groups %.6e pe:hier_total %.6e array_total %.6e" [expr {$s/$npe}] [expr {$pe_tot/$npe}] \
    [get_attribute [get_cells u_array] total_power]]
close $fh
exit
