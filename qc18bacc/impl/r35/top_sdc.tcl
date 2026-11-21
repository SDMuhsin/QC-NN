# R35 top SDC = impl/r11/top_sdc.tcl (period QB11_PER) with the R31 EMA fix: OpenSTA's */EMA* also matches the ARM
# macros' QA outputs (R29 / R30), so the case analysis is redone on the EMA / EMAA / EMAB bits only (as impl/r9b/sdc.py
# QB31_SDC 1).
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r11/top_sdc.tcl]
if {[llength $_e]} { unset_case_analysis $_e }
set _e [get_pins -quiet -hierarchical -regexp {.*/EMA[AB]?\[[0-9]+\]}]
if {[llength $_e]} { set_case_analysis 0 $_e }
