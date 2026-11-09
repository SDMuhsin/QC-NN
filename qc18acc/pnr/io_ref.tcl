# Host-port IO constraints referenced to the propagated clock at the host interface (P(QA_IO_REF) 1; sourced by
# post_cts.tcl after CTS, and by pt_post_qa.tcl with QA_IO_REF=1 after the synthesis SDC).  The synthesis SDC times the host-port input /
# output delays (20 % of the period) against the IDEAL clock edge at the clk pin; after CTS every register sees the
# propagated insertion delay (1.0-1.5 ns tt, ~1.5x at ss), so an input path appears to need that much extra hold
# delay (v2: thousands of hold buffers on host_* -> u_host) and output paths lose it from setup.  Here the delays
# are re-referenced to the clock arrival at the host interface register u_host/h1_addr_reg_0_/CP (-reference_pin):
# the host is modelled as synchronous logic on the same clock tree (same IO budget, no ideal-edge offset).
# OpenROAD (get_property) or PrimeTime (get_attribute; flat routed netlist: '/' inside instance names is escaped)
if {[info commands get_attribute] ne ""} {
    set qa_ref [get_pins -quiet {u_host\/h1_addr_reg_0_/CP}]
    if {![sizeof_collection $qa_ref]} { set qa_ref [get_pins u_host/h1_addr_reg_0_/CP] }
    set qa_io [expr {[get_attribute [get_clocks qa_clk] period] * 0.2}]
} else {
    set qa_ref [get_pins u_host/h1_addr_reg_0_/CP]
    set qa_io  [expr {[get_property [get_clocks qa_clk] period] * 0.2}]
}
if {[info commands get_attribute] ne ""} {
    set qa_in [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
    set qa_n [sizeof_collection $qa_in]
} else {
    set qa_in {}
    foreach p [all_inputs] { if {[get_full_name $p] ni {clk rst_n}} { lappend qa_in $p } }
    set qa_n [llength $qa_in]
}
set_input_delay  $qa_io -clock qa_clk -reference_pin $qa_ref $qa_in
set_output_delay $qa_io -clock qa_clk -reference_pin $qa_ref [all_outputs]
puts "QA_IO_REF: $qa_n inputs, delay $qa_io ns relative to u_host/h1_addr_reg_0_/CP"
