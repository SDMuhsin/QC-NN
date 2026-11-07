# PrimeTime PX hook (NN_PT_HOOK of nn/gls/pt_power.tcl, after update_power): power of every hierarchical cell of
# the GeMMX accelerator down to 7 levels below the cluster top (array tiles / butterflies / decoder, SIMD lanes and
# requant table, CSR manager, streamer readers / writers) -> ${OUT}_hook.txt (design hierarchy only, no kit names).
# Net capacitance: the wire-load setting of pt_power.tcl ($wlm: synthesis WLM, or zero with NN_PT_ZWLM=1).
# Columns: internal switching leakage total (W), the same quantities as report_power -hierarchy.
set G i_snax_core_0_acc_0_snax_streamer_gemmX
set fh [open $::env(OUT)_hook.txt w]
puts $fh "# hier cell, internal switching leakage total power (W) at period_ns $::env(QC_PERIOD) wire_load $::wlm"
foreach_in_collection c [add_to_collection [get_cells $G] [get_cells -hierarchical -filter "is_hierarchical==true && full_name=~$G/*"]] {
  set n [get_object_name $c]
  if {[regexp -all / $n] > 6} { continue }
  set v {}
  foreach a {internal_power switching_power leakage_power total_power} {
    if {[catch {set x [get_attribute $c $a]}] || $x eq ""} { set x NA }
    lappend v $x
  }
  puts $fh "$n [join $v { }]"
}
close $fh
