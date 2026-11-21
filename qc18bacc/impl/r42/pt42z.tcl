# R42 diagnostic QB_PT_EXTRA: hub in -> out (feed-through) arcs and paths, max vs min (pt39x found 0 setup / 26 hold).
set hub [get_cells -hierarchical -filter "ref_name==qb_hub"]
set hi [get_pins -of_objects $hub -filter "direction==in"]; set ho [get_pins -of_objects $hub -filter "direction==out"]
set ft [filter_collection [get_timing_arcs -of_objects $hub] "sense!~*clock* && sense!~*setup* && sense!~*hold* && from_pin.lib_pin_name!=clk"]
puts $fh "R42FT hub comb arcs [sizeof_collection $ft]"
set k 0; foreach_in_collection a $ft { if {$k < 5} { puts $fh "R42FT arc [get_object_name [get_attribute $a from_pin]] -> [get_object_name [get_attribute $a to_pin]] sense [get_attribute $a sense] dmax [get_attribute -quiet $a delay_max_rise]" }; incr k }
foreach dt {max min} {
    redirect -variable r { report_timing -delay_type $dt -max_paths 2 -nosplit -input_pins -through $hi -through $ho }
    puts $fh "##### R42FT $dt\n$r"
    set ft2 [get_timing_paths -delay_type $dt -through $hi -through $ho -max_paths 100000 -nworst 1]
    puts $fh "R42FT $dt paths [sizeof_collection $ft2]"
}
redirect -variable r { report_exceptions }
puts $fh "##### exceptions\n$r"
