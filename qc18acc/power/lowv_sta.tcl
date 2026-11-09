# PrimeTime timing of the QC18-ACC netlist at a low-voltage cell corner (driven by qc18acc/power/lowv.sh).
# Cells: QC_PT_LIB (e.g. tcbn65gplustc0d8_ccs = tt 0.8 V 25 C), synthesis WLM, synthesis SDC at QC_PERIOD.
# Macros: the ARM compilers of the kit are characterised only at ss 0.9 V / tt 1.0 V / ff 1.1 V, so the macro .db
# linked here are the tt 1.0 V views (QC_EXTRA_DB_TT): their arcs are NOT valid at 0.8 V.  Reported:
#   all      worst setup path of qa_clk (macro arcs at 1.0 V: optimistic, informative only)
#   logic    worst setup path that neither starts at a macro (CLK -> Q) nor ends at a macro input pin, i.e. the
#            logic-only fmax (cell and wire delays all at 0.8 V)
#   to_macro / from_macro  worst path into / out of a macro (with the 1.0 V macro setup / clock-to-Q)
# Environment: QC_FLOW, SYN (DC run dir), QC_SDC, QC_PERIOD, QC_PT_CORNER, QC_PT_LIB, QC_EXTRA_DB_TT, OUT (prefix),
#   QA_MACROS (macro cell names; default the v2 set, lowv.sh sets the v3 set for QA_V=3).
source $::env(QC_FLOW)/common/lib.tcl
set top qa_top
set corner [qc_env QC_PT_CORNER tt08]
set ::QC_LIB($corner) $::env(QC_PT_LIB)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs tt]]
read_verilog $::env(SYN)/$top.v
current_design $top
link_design
set ::env(QC_CORNER) $corner
qc_apply_constraints $corner
set wlm [qc_wire_load $corner]
update_timing
set o $::env(OUT)
set per [get_attribute [get_clocks qa_clk] period]
set mf {}; foreach m [qc_env QA_MACROS "qa_act_1024x64m8 qa_wgt_4096x80m8 qa_par_4096x72m8 qa_dsc_256x32m2"] { lappend mf "ref_name==$m" }
set mcs [get_cells -hierarchical -filter "is_hierarchical==false && ([join $mf { || }])"]
set mout [get_pins -of $mcs -filter "direction==out"]
set min  [get_pins -of $mcs -filter "direction==in"]
set fh [open ${o}.txt w]
puts $fh "design $top netlist $::env(SYN) corner $corner lib $::QC_LIB($corner) macros tt_1p0v (not 0.8 V) period_ns $per wire_load $wlm"
proc line {fh k p per} {
    if {![sizeof_collection $p]} { puts $fh "$k none"; return }
    set s [get_attribute $p slack]
    puts $fh [format "%s wns_ns %.3f fmax_mhz %.1f path %s -> %s" $k $s [expr {1000.0 / ($per - $s)}] \
        [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
}
line $fh all [get_timing_paths -delay_type max -max_paths 1 -group qa_clk] $per
# logic only: exclude every path through a macro output or into a macro input pin
set pl [get_timing_paths -delay_type max -max_paths 1 -group qa_clk -exclude [add_to_collection $mout $min]]
line $fh logic $pl $per
line $fh to_macro   [get_timing_paths -delay_type max -max_paths 1 -to $min] $per
line $fh from_macro [get_timing_paths -delay_type max -max_paths 1 -through $mout] $per
line $fh hold_all   [get_timing_paths -delay_type min -max_paths 1] $per
redirect ${o}_logic.rpt { report_timing -delay_type max -max_paths 5 -nosplit -exclude [add_to_collection $mout $min] }
redirect ${o}_all.rpt   { report_timing -delay_type max -max_paths 5 -nosplit }
close $fh
exit
