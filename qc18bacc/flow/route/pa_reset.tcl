# Pin-access reset before a global route of an ECO'd routed db (R49, results/r49.md).  A db that went through
# detailed_route carries DRT's pin access points: per instance a pin-access class (dbInst pin_access_idx) and per
# instance pin a preferred access point (dbITerm aps_, keyed by the master's dbMPin, offset from the instance origin).
# OpenROAD 2.0-12381 global_route places every pin at its odb access point when one exists (GlobalRouter::
# pinAccessPointPositions: preferred APs, else all APs of the instance's class) and at the pin-shape centre otherwise.
# odb never invalidates them: dbInst::swapMaster (resize), setLocation / setOrient (legalisation, row flips) keep both,
# and dbInst::create sets class 0 of the master.  After a repair + unrestricted legalisation the GRT pins of resized /
# moved / flipped / new cells sit where the OLD pin was, the guides miss the real pin, DRT patches the ones next to a
# guide (DRT-1000) and stops with DRT-0218 when no guide is within one gcell (DRT-1001; r48_act hold step, 4 tries).
# qb_pa_reset drops every instance's access data, so GRT uses the pin shapes (as on a never-routed db, e.g. the route
# step's cts_rt.odb); detailed_route recomputes pin access for every instance and writes it back (FlexPA, io::Writer).
# Sourced by every script that runs global_route on a db that was detailed-routed before (repair/hold_eco.tcl),
# after the last placement / netlist change and before global_route.
proc qb_pa_reset {} {
    set blk [ord::get_db_block]
    # a stale preferred AP is keyed by the object id of the OLD master's dbMPin (ids 1..n within each master; the Tcl
    # API has no getId): the pins of the master with the most pins cover every id
    set allmp {}
    foreach lib [[ord::get_db] getLibs] { foreach m [$lib getMasters] {
        set l {}; foreach mt [$m getMTerms] { foreach mp [$mt getMPins] { lappend l $mp } }
        if {[llength $l] > [llength $allmp]} { set allmp $l } } }
    set ni 0; set nt 0; set nres 0
    foreach i [$blk getInsts] {
        # class index beyond every master's class count: dbITerm::getAccessPoints() returns none
        $i setPinAccessIdx 1000000; incr ni
        foreach it [$i getITerms] {
            if {![llength [$it getPrefAccessPoints]]} continue
            incr nt
            foreach mp [[$it getMTerm] getMPins] { $it setAccessPoint $mp NULL }
            if {[llength [$it getPrefAccessPoints]]} { foreach mp $allmp { $it setAccessPoint $mp NULL } }
            if {[llength [$it getPrefAccessPoints]]} { incr nres }
        }
    }
    puts "QB_PA_RESET insts $ni pins_with_preferred_ap $nt left $nres"
    return $nres
}
qb_pa_reset
