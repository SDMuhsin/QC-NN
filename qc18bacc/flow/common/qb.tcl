# qc18bacc flow: Tcl helpers shared by every block config, hook and standalone OpenROAD script.
#   ::QBF       root of the qc18bacc flow (qc18bacc/flow), from QC_FLOW (flow/tsmc65, set by flow/tsmc65 common/tool.sh)
#   qb_env n d  environment variable n if it exists (even when empty), else d
set ::QBF [file normalize $::env(QC_FLOW)/../../qc18bacc/flow]
proc qb_env {n d} { return [expr {[info exists ::env($n)] ? $::env($n) : $d}] }
# Standard-cell liberty that OpenROAD reads (R48, results/r48.md): a copy of the kit CCS liberty whose input-pin capacitance
# is the CCS receiver-capacitance maximum PrimeTime loads nets with (common/lib_pincap.py), so OpenROAD's DRV / timing
# repair sees the sign-off load.  Built once per base corner (site.tcl QC_CORNERS) under $QC_BUILD/lib_pincap (kit-derived, stays on the build host).
proc qb_pincap_libs {} {
    if {![info exists ::QC_PNR_LIBDIR] || ![info exists ::QC_LIB]} return
    set d $::QC_BUILD/lib_pincap
    foreach c $::QC_CORNERS {
        set f $::QC_LIB($c)$::QC_PNR_LIBEXT
        if {![file exists $::QC_PNR_LIBDIR/$f]} continue
        if {![file exists $d/$f]} {
            file mkdir $d
            puts [exec $::env(QC_PY) -I $::QBF/common/lib_pincap.py $::QC_PNR_LIBDIR/$f $d/$f.tmp[pid]]
            file rename -force $d/$f.tmp[pid] $d/$f
        }
    }
    set ::QC_PNR_LIBDIR $d
}
qb_pincap_libs
