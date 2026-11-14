# R4 chip constraints: impl/constraints.sdc (slice recipe) + the rf_2p port-to-port clock checks disabled.
# The ARM rf_2p .lib constrains CLKB against CLKA (port clock separation).  Both port clocks are the chip clock through
# their own ICG (hw/tech/qb_mem_tech.sv); pre-CTS with an ideal clock this check is evaluated as a clock-as-data path
# from the clk port through the ICG (72 ns of unbuffered clk-port delay) and is meaningless; it belongs to CTS
# (skew between the two gated clocks), so paths ending at CLKA / CLKB are false paths here (data pins AA, AB, DB, WENB keep their checks).
source [file dirname [info script]]/../constraints.sdc
set rf2p [get_cells -quiet -hierarchical -filter "is_hierarchical==false && (ref_name==qb_s_256x128m1 || ref_name==qb_b_128x128m1)"]
if {[sizeof_collection $rf2p]} {
    set_false_path -to [filter_collection [get_pins -of_objects $rf2p] "lib_pin_name==CLKA || lib_pin_name==CLKB"]
}
