# R27: worst in2reg path of db/place.odb (ideal clocks, QB_IO_LAT): per point master / delay step (R27_P lines).
rename exit qb27_exit
proc exit {args} {}
source $::env(QC_FLOW)/../../qc18bacc/impl/r21/sta_cls.tcl
set pe [lindex [find_timing_paths -path_delay max -from [all_inputs] -to [all_registers] -group_count 1000000 -endpoint_count 1 -slack_max -1.0 -sort_by_slack] 0]
puts "R27_P slack [get_property $pe slack] start [get_full_name [get_property $pe startpoint]]"
set prev 0
foreach p [get_property $pe points] {
    set pin [get_property $p pin]; set a [get_property $p arrival]
    set m [expr {[$pin is_top_level_port] ? "PORT" : [get_property [$pin instance] ref_name]}]
    puts [format "R27_P %-10s %-12s arr %.3f step %.3f" $m [regsub -all {[0-9]+} [get_full_name $pin] N] $a [expr {$a - $prev}]]
    set prev $a
}
qb27_exit
