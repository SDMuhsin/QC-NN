# R35 PIN_TCL of impl/r35/col.cfg: the column's own pins.tcl (impl/r5a), then every signal pin moved to the position it
# has in the reference abstract (QB35_COLPINS: place_pin list from impl/r35/colpins.py on r5b_blk/qb_col_blk_ring.lef),
# so the re-run column abuts the hub / act / neighbour columns exactly as the r5b_blk views they were built against.
source $::QB5_DIR/pins.tcl
set _t [clock seconds]; set _n 0; set _e 0
set _f [open $::env(QB35_COLPINS)]
while {[gets $_f _l] >= 0} {
    if {[string match "#*" $_l] || $_l eq ""} continue
    if {[catch {eval $_l} _m]} { incr _e; if {$_e < 5} { qc_log "r35 colpins error: $_m" } } else { incr _n }
}
close $_f
qc_log "r35 colpins: $_n pins placed from $::env(QB35_COLPINS), $_e errors ([expr {[clock seconds] - $_t}] s)"
