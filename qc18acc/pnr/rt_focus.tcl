# Focused setup repair (P(QA_RT_FOCUS) 1; sourced by post_cts.tcl and post_grt.tcl before the normal repair_timing
# -setup).  v2 / v3: OpenROAD's repair_timing works the worst endpoint first and gives up when its slack stops
# improving (RSZ-0062): after CTS the worst endpoints are paths launched by a macro (weight SRAM CLK -> Q -> 1 mm of
# wire to the head) or host-port IO paths, which sizing cannot fix, so it stopped after ~250 resizes with 15 800
# violating endpoints left (with -repair_tns 100 it spent 3 500 passes on u_head/dot2_reg without a WNS change).
# Here those paths are false-pathed for one repair_timing pass (only logic-launched paths into registers / ICGs
# remain, e.g. xbar -> PE rotators -> adders -> accumulator, whose D0 / D1 cells drive routed wires), then the
# exceptions are removed and the normal repair runs as before.
set qa_mclk {}; set qa_min {}
foreach i [[ord::get_db_block] getInsts] {
    if {[[$i getMaster] isBlock]} {
        lappend qa_mclk [get_pins [$i getName]/CLK]
        foreach it [$i getITerms] {
            if {[$it isInputSignal] && [[$it getMTerm] getName] ne "CLK"} { lappend qa_min [get_pins [$i getName]/[[$it getMTerm] getName]] }
        }
    }
}
set_false_path -from $qa_mclk
set_false_path -to $qa_min
set_false_path -from [all_inputs]
set_false_path -to [all_outputs]
puts "QA_RT_FOCUS: [llength $qa_mclk] macro clocks, [llength $qa_min] macro inputs and the IO excluded for one repair_timing -setup pass"
repair_timing -setup -setup_margin [p SETUP_MARGIN] -max_utilization [p MAX_UTIL] {*}[p QA_RT_ARGS {}]
unset_path_exceptions -from $qa_mclk
unset_path_exceptions -to $qa_min
unset_path_exceptions -from [all_inputs]
unset_path_exceptions -to [all_outputs]
