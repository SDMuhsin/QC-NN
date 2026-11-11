# Extra hold margin at the SRAM / RF macro clock pins for OpenROAD's hold repair (P(QA_MACRO_HOLD) ns > 0; sourced by
# post_cts.tcl and post_grt.tcl).  v2 routed: 129 of the 139 tt hold violations (PT, SPEF) end at macro D / A pins
# (host write data -> weight macro D, AGU -> act macro A), -0.13 ns worst, all met at the global-route estimate:
# the macro clock is a 1-sink net from its CKLNQD2 (CTS skips it), the macro hold time is 0.21 ns and the routed
# clock / data wires differ from the global-route estimate.  The margin is a hold-only clock uncertainty on the macro
# CLK pins (only paths captured by a macro get it); the sign-off PT run keeps the synthesis SDC.
# P(QA_MACRO_HOLD_RE): only the macro instances matching this regexp (default all; v4 qa4c.cfg: the weight / param
# macros, whose pins also carry the netlist SDC's 0.4-ns min delay; on all 57 v4 macros the margin made 11 349 hold
# endpoints and a > 75-min hold repair).
set qa_mclk {}
foreach i [[ord::get_db_block] getInsts] {
    if {[[$i getMaster] isBlock] && [regexp [p QA_MACRO_HOLD_RE .] [$i getName]]} { lappend qa_mclk [get_pins [$i getName]/CLK] }
}
set_clock_uncertainty -hold [expr {[qc_env QC_UNC_HOLD 0.05] + [p QA_MACRO_HOLD]}] $qa_mclk
puts "QA_MACRO_HOLD: +[p QA_MACRO_HOLD] ns hold uncertainty on [llength $qa_mclk] macro CLK pins"
