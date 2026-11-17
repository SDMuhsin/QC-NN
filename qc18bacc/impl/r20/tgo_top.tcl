# R20 (results/r20.md): read-only probe of the R14 top (r14_k, GRT db) for the act block's control inputs (tgo, l_ok,
# start, c_*): arrival at the block pin = top clock latency at the driving flop + clk->Q + top wire (GRT parasitics),
# vs the block budget QB7_CIN 0.40 P + L.  Same loading as impl/r14/probe_path.tcl.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qb_env QB_DB grt]
if {[catch {estimate_parasitics -global_routing}]} { estimate_parasitics -placement }
set_propagated_clock [all_clocks]
set blk [ord::get_db_block]
set act ""
foreach i [$blk getInsts] { if {[[$i getMaster] getName] eq "qb_act2_blk"} { set act [$i getName] } }
puts "R20TGO act instance $act"
foreach p [qb_env QB20_PINS {tgo[0] tgo[1] l_ok[0] l_ok[1]}] {
    set dn [get_nets -of_objects [get_pins -quiet "$act/$p"]]
    foreach dp [get_pins -quiet -of_objects $dn] {
        if {[get_property $dp direction] eq "output" && ![string match u_act_blk/* [get_full_name $dp]]} {
            puts "R20TGO driver [get_full_name $dp] [get_property [get_cells -of_objects $dp] ref_name]"
            # top-side arrival at the driver output (proxy block pins carry no usable arc): min / max, propagated clock
            report_checks -path_delay min -unconstrained -through $dp -format full_clock_expanded -digits 3
            report_checks -path_delay max -unconstrained -through $dp -format full_clock_expanded -digits 3
        }
    }
    set pin [get_pins -quiet "$act/$p"]
    if {$pin eq ""} { puts "R20TGO $p not found"; continue }
    set net [get_nets -of_objects $pin]
    puts "R20TGO pin $p net [get_full_name $net]"
}
