# R4b: impl/r4/constraints.sdc + a report of the macro clock-pin false paths (DC and PT attribute names differ)
source [file dirname [info script]]/../r4/constraints.sdc
set rf2p [get_cells -quiet -hierarchical -filter "is_hierarchical==false && (ref_name==qb_s_256x128m1 || ref_name==qb_b_128x128m1)"]
puts "QB_SDC rf2p [sizeof_collection $rf2p] clkpins_lib [sizeof_collection [filter_collection [get_pins -quiet -of_objects $rf2p] {lib_pin_name==CLKA || lib_pin_name==CLKB}]] clkpins_name [sizeof_collection [get_pins -quiet -of_objects $rf2p -filter {name==CLKA || name==CLKB}]]"
