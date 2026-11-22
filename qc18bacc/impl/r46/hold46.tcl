# R46 repro of the r43_a repair_timing -hold SEGFAULT (results/r46.md): impl/r43/hold43.tcl with the resizer's hold
# debug trace on (RSZ repair_hold level R46_HDBG [3]: one line per endpoint repaired and per driver tried), so the
# last lines before the crash name the endpoint / driver.  Same knobs as hold43 (R43_HGRT0, R43_HINC, QB43_GRTANT).
set_debug_level RSZ repair_hold [expr {[info exists ::env(R46_HDBG)] ? $::env(R46_HDBG) : 3}]
source $::env(QC_FLOW)/../../qc18bacc/impl/r43/hold43.tcl
