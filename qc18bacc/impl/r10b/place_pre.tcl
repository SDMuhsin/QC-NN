# PRE_PLACE_TCL of impl/r10b/hub.cfg: impl/r9b/place_pre.tcl (max transition, remove_buffers, incremental gpl + DRV
# repair, QB9_CHBLK channel blockages, QB9_GPL2) + the R10b S-read structural placement (impl/r10b/srd.tcl, QB10_SRD 1).
source $::QB_R9B/place_pre.tcl
if {[qb_env QB10_SRD 1]} { source $::QB_R10B/srd.tcl }
