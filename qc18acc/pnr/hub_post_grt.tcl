# POST_GRT_TCL of qa3c.cfg: post_grt.tcl (its legalisation still sees the hub padding), then the padding is cleared
# before filler_placement / check_placement of route.tcl (see hub_pad.tcl).
set d [file normalize $::env(QC_FLOW)/../../qc18acc/pnr]
source $d/post_grt.tcl
set ::qa_hub_lib_only 1
source $d/hub_pad.tcl
qa_hub_pad 0
