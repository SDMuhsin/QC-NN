# Lib-cell lists shared by ICC2 (flow/icc2/common.tcl) and PrimeTime (signoff/pt/drv_eco.tcl, col_blk.tcl), sourced after
# site.tcl (QC_DONT_USE) and site/pnr.tcl (QC_PNR_CTS_BUF); both tools resolve the names on their loaded libraries.
#   qb_dont_use_match <cell>  1 if the lib-cell name matches a QC_DONT_USE glob
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
#                             no design instance is one (every step); returns the "dont_use <tag> ..." line, error otherwise
proc qb_dont_use_match {c} {
    foreach g $::QC_DONT_USE { if {[string match $g $c]} { return 1 } }
    return 0
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
    set n 0; set bad {}
    if {$lib} {
        foreach g $::QC_DONT_USE {
            foreach_in_collection lc [get_lib_cells -quiet */$g] {
                incr n
                set du [get_attribute -quiet $lc dont_use]
                set vp [expr {$icc2 ? [get_attribute -quiet $lc valid_purposes] : ""}]
                if {$du ne "true" || $vp ne ""} { lappend bad "[file tail [get_object_name $lc]]:dont_use=$du:purposes=[join $vp ,]" }
            }
        }
    }
    set f [join [lmap g $::QC_DONT_USE { string cat "ref_name=~" $g }] " || "]
    set ic [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ($f)"]
    set l "dont_use $tag lib_cells $n usable [llength $bad] [lrange $bad 0 3] design_cells [sizeof_collection $ic]"
    puts "QB_DONT_USE_GATE $l"
    if {[llength $bad] || [sizeof_collection $ic]} { error "QB dont_use gate $tag: [llength $bad] usable dont_use lib cells, [sizeof_collection $ic] instances ($l)" }
    return $l
}
