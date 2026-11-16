# PRE_CTS_TCL of impl/r9b/hub.cfg: ICG sizing by gated-sink count + move to the sink centroid (impl/r6c/icg.tcl,
# QB_ICG 1 default), legalised by the CTS step's detailed placement.
if {[qb_env QB_ICG 1]} { source $::QB_R6C/icg.tcl; qb6c_icg }
