# R11 probe (read-only on the run; own db copy not written): global placement only (no DRV repair) of db/pdn.odb with
# QB_GPL_ARGS, then standard-cell count / area per fp11 region (probe_place.tcl regions): cells whose centre lies in
# the hub / array / act footprints are inside fixed blocks (no legal site there).
read_db $::env(QC_PNR_OUT)/db/pdn.odb
set_thread_count [expr {[info exists ::env(QC_PNR_THREADS)] ? $::env(QC_PNR_THREADS) : 4}]
remove_buffers
global_placement -density 0.55 -skip_io {*}[expr {[info exists ::env(QB_GPL_ARGS)] ? $::env(QB_GPL_ARGS) : "-overflow 0.2"}]
set ::env(QB_DB) none
source $::env(QB11_DIR)/probe_place.tcl
