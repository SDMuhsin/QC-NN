# OCV timing derate of every P&R and sign-off timer (R64, PI decision: the kit has no AOCV / POCV tables, so the standard
# flat 65 nm derate): late 1.05 / early 0.95 on cell and net delays, clock and data paths (no -clock / -data: both),
# on top of the clock uncertainty of constraints.sdc.  Sourced by flow/icc2/common.tcl (qb_timer: every scenario, so
# place_opt / clock_opt / route_opt optimise with it) and signoff/pt/common.tcl (block sign-off, DMSA ECO, ETMs, top).
#   qb_derate   set_timing_derate of the current corner (PrimeTime: the design; ICC2: the current scenario's corner)
set ::QB_DERATE_LATE  1.05
set ::QB_DERATE_EARLY 0.95
proc qb_derate {} {
    set_timing_derate -late  -cell_delay -net_delay $::QB_DERATE_LATE
    set_timing_derate -early -cell_delay -net_delay $::QB_DERATE_EARLY
}
