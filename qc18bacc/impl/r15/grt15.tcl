# R15 GRT-only rerun (run15.sh grt): impl/r10b/grt.tcl unchanged, with an optional per-layer GRT adjustment on top of
# its uniform QB_GADJ [0.25]: QB15_GADJ_L "M5-M9 0.10" (pairs <layer range> <adj>, applied after the uniform call).
# Default (unset): identical to impl/r10b/grt.tcl.  The pin-access layers (M2-M4) keep the uniform value.
if {[info exists ::env(QB15_GADJ_L)] && $::env(QB15_GADJ_L) ne "" && [info commands qb15_gadj_orig] eq ""} {
    rename set_global_routing_layer_adjustment qb15_gadj_orig
    proc set_global_routing_layer_adjustment {layers adj} {
        qb15_gadj_orig $layers $adj
        puts "R15 gadj $layers $adj"
        foreach {l a} $::env(QB15_GADJ_L) { qb15_gadj_orig $l $a; puts "R15 gadj $l $a (QB15_GADJ_L)" }
    }
}
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r10b/grt.tcl]
