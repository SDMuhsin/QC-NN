# PRE_ROUTE_TCL of blocks/col/col.cfg: post-CTS repair (repair/post_cts.tcl, IO budget shifted by QB_IO_LAT), then the
# per-layer GRT adjustment QB15_GADJ_L (route/gadj_layers.tcl) for the flow's global route.
source $::QBF/repair/post_cts.tcl
source $::QBF/route/gadj_layers.tcl
