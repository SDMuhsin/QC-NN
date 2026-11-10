# PRE_ROUTE_TCL of qa3c.cfg: hub padding again (not stored in the odb, see hub_pad.tcl), then post_cts.tcl.
set d [file normalize $::env(QC_FLOW)/../../qc18acc/pnr]
set ::qa_hub_lib_only 1
source $d/hub_pad.tcl
qa_hub_pad [p QA_HUB_PAD]
source $d/post_cts.tcl
