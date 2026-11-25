# Lib-cell lists shared by ICC2 (flow/icc2/common.tcl) and PrimeTime (signoff/pt/drv_eco.tcl, col_blk.tcl), sourced after
# site.tcl (QC_DONT_USE) and site/pnr.tcl (QC_PNR_CTS_BUF); both tools resolve the names on their loaded libraries.
#   qb_dont_use_match <cell> [hold]  1 if the lib-cell name matches a QC_DONT_USE glob (hold 1: the QC_HOLD_ONLY globs excepted)
#   qb_hold_only              the QC_HOLD_ONLY globs (site.tcl, R84: DEL*): globs of QC_DONT_USE that hold fixing alone may
#                             use; error unless each is a QC_DONT_USE glob (so DC and every other use keep them dont_use)
#   qb_hold_cells             the ONE hold-fixing cell list (R84): the library's data buffers BUFFD<n> and delay cells DEL<n>,
#                             minus QC_DONT_USE (QC_HOLD_ONLY excepted).  ICC2 hold fixing (icc2/init.tcl: lib-cell purpose
#                             hold = exactly these; the hold-only cells have no other purpose) and the PrimeTime hold ECO
#                             (signoff/pt/drv_eco.tcl -buffer_list, hold-only cells dont_use outside the hold pass) use it.
#                             Clock buffers CK* are not hold cells (clock-tree family, qb_clock_cells): r82 ICC2 had used
#                             CKBD0 for hold because every non-dont_use cell had the hold purpose.
#   qb_clock_cells            clock-tree lib cells by exact family (R77): the CTS buffers QC_PNR_CTS_BUF (each CKBD<n>), the
#                             clock inverters CKND<n> and the clock gates CKLNQD<n>, minus QC_DONT_USE.  ICC2 CTS uses only
#                             these (icc2/cts.tcl), and so does the sign-off ECO in the clock network (drv_eco.tcl
#                             qb_eco_drc: r75 eco 1 without the restriction sized a clock inverter to INVD8 [M]).  R75's
#                             globs CKND* / CKLNQD* also matched the CKND2D<n> NAND gates and the kit dont_use CKND20 / 24,
#                             CKLNQD20 / 24, and cts.tcl's include re-enabled those for CTS over init's exclusion (R77 [M],
#                             r75 cts.log ATTR-12; ICC2 valid_purposes of CKND20 / CKLNQD20 = cts on the r75 labels)
#   qb_lib_tcq <corner>       fastest clock -> Q (ns, no derate) of the corner's library flip-flops that are not dont_use
#                             (common/lib_tcq.py on the liberty text QC_LIBDIR/QC_LIB(corner).lib; the period-independent
#                             min input delay, blocks/col/io_budget.tcl), cached as $QC_BUILD/lib_tcq/<lib>.txt (kit-derived:
#                             stays on the build host); R77 [M] lt 0.033 ns, wc 0.079 ns (SDFQND1 CP -> QN)
#   qb_dont_use_gate <tag> <lib>  dont_use gate (R77): no lib cell matching QC_DONT_USE is usable (lib 1: ICC2 dont_use
#                             true and no valid_purposes; PrimeTime dont_use true, where the step optimises, the ECO) and
#                             no design instance is one (every step); R84: a QC_HOLD_ONLY cell is ICC2 purpose hold only
#                             (not dont_use) and may be instantiated (counted); returns the "dont_use <tag> ..." line, error otherwise
proc qb_dont_use_match {c {hold 0}} {
    set h [expr {$hold ? [qb_hold_only] : {}}]
    foreach g $::QC_DONT_USE { if {[string match $g $c] && [lsearch -exact $h $g] < 0} { return 1 } }
    return 0
}
proc qb_hold_only {} {
    foreach g $::QC_HOLD_ONLY { if {[lsearch -exact $::QC_DONT_USE $g] < 0} { error "qb_hold_only: QC_HOLD_ONLY glob $g is not a QC_DONT_USE glob" } }
    return $::QC_HOLD_ONLY
}
proc qb_hold_cells {} {
    set c {}
    foreach n [lsort -unique [lmap x [get_object_name [get_lib_cells -quiet {*/BUFFD* */DEL*}]] { file tail $x }]] {
        if {[regexp {^(BUFFD|DEL)\d+$} $n] && ![qb_dont_use_match $n 1]} { lappend c $n }
    }
    if {![llength $c]} { error "qb_hold_cells: no hold cell in the loaded libraries" }
    return [lsort -dictionary $c]
}
proc qb_clock_cells {} {
    foreach b $::QC_PNR_CTS_BUF { if {![regexp {^CKBD\d+$} $b]} { error "qb_clock_cells: CTS buffer $b is not a CKBD<n>" } }
    set c {}
    foreach n [lsort -unique [lmap x [get_object_name [get_lib_cells -quiet */CK*]] { file tail $x }]] {
        if {([lsearch -exact $::QC_PNR_CTS_BUF $n] >= 0 || [regexp {^(CKND|CKLNQD)\d+$} $n]) && ![qb_dont_use_match $n]} { lappend c $n }
    }
    return [lsort -dictionary $c]
}
set ::QB_LIB_CELLS_DIR [file normalize [file dirname [info script]]]
proc qb_lib_tcq {corner} {
    set lib $::QC_LIB($corner)
    set d $::env(QC_BUILD)/lib_tcq; set f $d/$lib.txt
    if {![file exists $f]} {
        file mkdir $d
        set t [exec $::env(QC_PY) -I $::QB_LIB_CELLS_DIR/lib_tcq.py $::QC_LIBDIR/$lib.lib {*}$::QC_DONT_USE]
        set h [open $f.tmp[pid] w]; puts $h $t; close $h; file rename -force $f.tmp[pid] $f
    }
    set h [open $f]; set t [string trim [read $h]]; close $h
    puts "QB_LIB_TCQ $corner $lib $t"
    return [lindex $t 0]
}
proc qb_dont_use_gate {tag lib} {
    set icc2 [string match icc2* $::synopsys_program_name]
    set ho [qb_hold_only]
    set n 0; set bad {}
    if {$lib} {
        foreach g $::QC_DONT_USE {
            set h [expr {[lsearch -exact $ho $g] >= 0}]
            foreach_in_collection lc [get_lib_cells -quiet */$g] {
                incr n
                set du [get_attribute -quiet $lc dont_use]
                set vp [expr {$icc2 ? [get_attribute -quiet $lc valid_purposes] : ""}]
                # hold-only cell (R84): in ICC2 not dont_use, lib-cell purpose hold and nothing else (icc2/init.tcl); in
                # PrimeTime dont_use like the rest (drv_eco.tcl lifts it for the hold pass only)
                set ok [expr {$h && $icc2 ? ($du ne "true" && [llength $vp] == 1 && [lindex $vp 0] eq "hold") : ($du eq "true" && $vp eq "")}]
                if {!$ok} { lappend bad "[file tail [get_object_name $lc]]:dont_use=$du:purposes=[join $vp ,]" }
            }
        }
    }
    # design instances: none of QC_DONT_USE; hold-only cells (hold fixing) are counted, not gated
    set f [join [lmap g $::QC_DONT_USE { if {[lsearch -exact $ho $g] >= 0} continue; string cat "ref_name=~" $g }] " || "]
    set ic [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ($f)"]
    set hc 0
    if {[llength $ho]} {
        set hc [sizeof_collection [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ([join [lmap g $ho { string cat "ref_name=~" $g }] " || "])"]]
    }
    set l "dont_use $tag lib_cells $n usable [llength $bad] [lrange $bad 0 3] design_cells [sizeof_collection $ic] hold_only_design_cells $hc"
    puts "QB_DONT_USE_GATE $l"
    if {[llength $bad] || [sizeof_collection $ic]} { error "QB dont_use gate $tag: [llength $bad] usable dont_use lib cells, [sizeof_collection $ic] instances ($l)" }
    return $l
}
