# R14 probe (read-only): one full path report through a given pin (QB14_THRU) on <run>/db/<QB_DB> [grt] with
# placement parasitics (QB14_PAR placement) -> stdout.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qb_env QB_DB grt]
estimate_parasitics -placement
foreach t [split [qb_env QB14_THRU u_hub/u_top_g_r3b_t2_s_391_] ,] {
    report_checks -path_delay max -through [get_pins $t] -format full_clock_expanded -fields {slew cap fanout input_pins} -digits 3
}
