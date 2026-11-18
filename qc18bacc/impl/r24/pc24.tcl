# R24 (results/r24.md): QB_PC_HOOK of impl/pnr/slice_post_cts.tcl (sourced after the IO delays + qb_* procs).
# QB24_MODE
#   meas    pn2 replay of QB_RTSEQ 2 up to the first hold legalisation, with dumps (dump24.tcl) for disp24.py:
#           hold classes (pre), setup repair -> d_su, legal -> d_sl (+ db r24_sl.odb), hold classes, hold repair ->
#           d_hu (+ db r24_hu.odb), legal -> d_hl (+ db r24_hl.odb), worst setup report
#   (the hold legalisation is qb24_fix_legal: QB24_FIX unset = qb_legal)
#   hmeas   the same from the loaded db without the setup repair (QB24_SKIP_SETUP semantics; fast proxy, or on a
#           loaded r24_sl.odb = the post-setup-legal state)
#   fix     QB_RTSEQ 2 sequence with the R24 fix (QB24_FIX, see qb24_fix_legal) in place of every qb_legal
# QB24_SKIP_SETUP 1: start at the hold repair (db already setup-repaired + legalised, e.g. r24_sl.odb as cts.odb)
set ::QB24_DIR [file dirname [file normalize $::env(QB_PC_HOOK)]]
source $::QB24_DIR/dump24.tcl
set ::QB24_D $::OUT/r24; file mkdir $::QB24_D
set mode [qb_env QB24_MODE meas]
proc qb24_rpt {tag} {
    qc_to $::QB24_D/$tag.setup.rpt { report_checks -path_delay max -fields {input_pins slew cap fanout} -digits 3 -group_count 3 -endpoint_count 1 }
}
# --- fix: R24 legalisation of repair cells (QB24_FIX)
#   pre  new / moved cells over a macro (+ halo) are moved to the nearest macro-free point (x or y) before DPL
#   legal detailed_placement with [QB24_DPL_ARGS] (default P(DPL_ARGS))
source $::QB24_DIR/fix24.tcl
# QB24_HOLD_DMIN d (ns, H3): every set_input_delay -min of the IO budget is re-applied + d (measured gated CP latency
# mean 1.404 vs QB_IO_LAT 1.30 -> d 0.10); -max / outputs unchanged
if {[qb_env QB24_HOLD_DMIN 0] != 0} {
    rename set_input_delay qb24_sid_orig
    proc set_input_delay {args} {
        set i [lsearch -exact $args -min]
        if {$i >= 0} {
            lset args [expr {$i + 1}] [expr {[lindex $args [expr {$i + 1}]] + $::env(QB24_HOLD_DMIN)}]
            qb24_sid_orig {*}$args
        }
    }
    qb5_io_apply $per $L
    rename set_input_delay ""; rename qb24_sid_orig set_input_delay
    qb_counts postcts_hold_dmin_[qb_env QB24_HOLD_DMIN 0]
}
if {$mode eq "meas" || $mode eq "hmeas"} {
    qb24_geom $::QB24_D/geom.txt
    if {!([qb_env QB24_SKIP_SETUP 0] || $mode eq "hmeas")} {
        qb24_cls $::QB24_D/hold_cls_pre.txt
        qb24_dump $::QB24_D/d_pre.txt
        qb_setup
        qb_counts postcts_setup_repair
        qb24_dump $::QB24_D/d_su.txt
        qb_legal postcts_setup_legal
        write_db $::OUT/db/r24_sl.odb
    }
    qb24_dump $::QB24_D/d_sl.txt
    qb24_cls $::QB24_D/hold_cls_sl.txt
    qb24_cls $::QB24_D/setup_cls_sl.txt max
    qb24_rpt sl
    qb_hold
    qb_counts postcts_hold_repair_unlegal
    qb24_dump $::QB24_D/d_hu.txt
    write_db $::OUT/db/r24_hu.odb
    qb24_fix_legal postcts_hold_legal
    qb24_dump $::QB24_D/d_hl.txt
    qb24_rpt hl
    qb24_cls $::QB24_D/setup_cls_hl.txt max
    write_db $::OUT/db/r24_hl.odb
    qc_log "r24: meas done"
    exit
}
if {$mode eq "fix"} {
    if {![qb_env QB24_SKIP_SETUP 0]} {
        qb_setup
        qb_counts postcts_setup_repair
        qb24_fix_legal postcts_setup_legal
    }
    qb_hold
    qb_counts postcts_hold_repair_unlegal
    qb24_fix_legal postcts_hold_legal
    for {set k 1} {$k <= [qb_env QB_RT_LOOPS 1]} {incr k} {
        qb_setup
        qb_counts postcts_setup${k}_repair
        qb24_fix_legal postcts_setup${k}_legal
        set nh 0; catch { set nh [sta::endpoint_violation_count min] }
        if {$nh > 0} { qb_hold; qb_counts postcts_hold${k}_unlegal; qb24_fix_legal postcts_hold${k}_legal }
    }
    check_placement
}
