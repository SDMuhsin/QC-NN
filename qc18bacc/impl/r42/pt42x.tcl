# R42 QB_PT_EXTRA for impl/r5b/pt_chip.tcl: impl/r39/pt39x.tcl (R37 conditions, violators, R39LAT) + a sample of the nets
# PT reports as not annotated (rpt/r42_<corner>_notann.rpt) and per-class hold / setup violator counts are in r39 viol.txt.
source [file normalize [file dirname [info script]]/../r39/pt39x.tcl]
redirect $dir/rpt/r42_${corner}_notann.rpt { report_annotated_parasitics -list_not_annotated -max_nets 3000 }
