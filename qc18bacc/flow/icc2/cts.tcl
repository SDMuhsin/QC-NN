# Clock tree + post-CTS optimisation: clock_opt (CTS with the site/pnr.tcl clock buffers, CKND inverters and the
# netlist's CKLNQD gates; setup / hold / DRV in the MCMM scenarios; I/O latency = median sink latency, ICC2's
# compute_clock_latency, which the IO budget assumes), no useful skew.  Block label place -> cts.
source [file dirname [info script]]/common.tcl
qb_open place cts
set_lib_cell_purpose -exclude cts [get_lib_cells */*]
set ck {}; foreach c [concat $::QC_PNR_CTS_BUF {CKND* CKLNQD*}] { lappend ck */$c }
set_lib_cell_purpose -include cts [get_lib_cells $ck]
set_app_options -name clock_opt.flow.enable_ccd -value false
qb_io_load
clock_opt
compute_clock_latency
redirect $::R/rpt/cts_clock_qor.rpt { report_clock_qor -type summary }
foreach l [split [exec cat $::R/rpt/cts_clock_qor.rpt] "\n"] { if {[regexp {qb_clk} $l]} { qb_line "cts [regsub -all {\s+} [string trim $l] { }]" } }
qb_qor cts
qb_done cts
