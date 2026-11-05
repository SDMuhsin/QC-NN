# init: libraries (all corners), LEF, netlist, SDC, per-corner RC.
qc_read_libs
qc_read_design
qc_set_rc
qc_read_sdc
qc_report init
qc_summary "init [join [qc_timing_lines init] { | }]"
