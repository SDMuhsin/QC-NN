# R9b: south-hub partition of the r8a_rp chip netlist in DC (no re-synthesis, no optimisation): ungroup u_top one
# level, flatten u_top/u_core (8 column-block leaf cells + DC buffers), group the hub cells (impl/r9b/part.py
# <W>/hub_cells.txt) into one instance u_hub of a new design qb_hub; write both netlists, the hub ports and the hub
# SDC (characterize in the chip context = the r8a_rp DC constraints incl. column ETMs).
# env: QB_SYN_DIR (syn/r8a_rp), QB_W (work dir), QC_EXTRA_DB_TT (run.env)
source $::env(QC_FLOW)/common/lib.tcl
set W $::env(QB_W)
set_app_var search_path [list . $::QC_LIBDIR]
set_app_var target_library [qc_db tt]
set_app_var link_library [concat * [qc_db tt] [qc_extra_dbs tt]]
set_svf $W/r9b.svf
read_ddc $::env(QB_SYN_DIR)/qb_chip.ddc
current_design qb_chip
link
puts "R9B cells before [sizeof_collection [get_cells -hierarchical -filter is_hierarchical==false]]"
ungroup u_top
ungroup -flatten [get_cells u_top/u_core]
puts "R9B top-level cells after ungroup [sizeof_collection [get_cells *]]"
set f [open $W/hub_cells.txt]; set names [split [string trim [read $f]] "\n"]; close $f
set cells [get_cells $names]
puts "R9B hub units found [sizeof_collection $cells] of [llength $names]"
group $cells -design_name qb_hub -cell_name u_hub
current_design qb_chip
link
puts "R9B leaf cells after [sizeof_collection [get_cells -hierarchical -filter is_hierarchical==false]]"
# broadcast hub outputs (one hub pin -> pins of several columns): one port + one buffer per further column, so that
# every column's south pins connect straight up to their own hub pins (QB_SPLIT 1)
if {[qc_env QB_SPLIT 1]} {
    set nsp 0
    set bufref [get_lib_cells */[qc_env QB_SPLIT_BUF BUFFD4]]
    # pass 1 (no netlist edits inside a collection loop): {hub pin name, top net, {column k -> load pins}}
    set todo {}
    foreach_in_collection hp [get_pins u_hub/* -filter "pin_direction==out"] {
        set pn [get_attribute $hp lib_pin_name]
        set tn [get_object_name [get_nets -of_objects $hp]]
        array unset cl
        foreach_in_collection l [get_pins -of_objects [get_nets $tn] -filter "pin_direction==in"] {
            if {[regexp {g_c_(\d+)__u_col} [get_object_name [get_cells -of_objects $l]] -> k]} { lappend cl($k) [get_object_name $l] }
        }
        set ks [lsort -integer [array names cl]]
        if {[llength $ks] < 2} continue
        set e {}; foreach k [lrange $ks 1 end] { lappend e $k $cl($k) }
        lappend todo [list $pn $tn $e]
    }
    puts "R9B broadcast hub outputs: [llength $todo]"
    # pass 2: hub ports + buffers (one current_design switch), pass 3: top-level reconnection
    current_design qb_hub
    foreach t $todo {
        lassign $t pn tn e
        set inet [get_object_name [get_nets -of_objects [get_ports $pn]]]
        foreach {k pins} $e {
            set np ${pn}_c$k; regsub -all {[][/\\]} $np _ np
            create_port $np -direction out
            create_net n_$np
            create_cell r9b_sb_$np $bufref
            connect_net [get_nets $inet] [get_pins r9b_sb_$np/I]
            connect_net [get_nets n_$np] [get_pins r9b_sb_$np/Z]
            connect_net [get_nets n_$np] [get_ports $np]
        }
    }
    current_design qb_chip
    foreach t $todo {
        lassign $t pn tn e
        foreach {k pins} $e {
            set np ${pn}_c$k; regsub -all {[][/\\]} $np _ np
            create_net t_$np
            foreach l $pins { disconnect_net [get_nets $tn] [get_pins $l]; connect_net [get_nets t_$np] [get_pins $l] }
            connect_net [get_nets t_$np] [get_pins u_hub/$np]
            incr nsp
        }
    }
    current_design qb_chip
    link
    puts "R9B split broadcast ports: $nsp new hub ports / buffers"
}
write -format ddc -hierarchy -output $W/qb_chip_r9b.ddc
change_names -rules verilog -hierarchy -log_changes $W/change_names.log
write -format verilog -hierarchy -output $W/qb_chip_r9b.v
set fo [open $W/hub_ports.txt w]
foreach_in_collection p [get_pins u_hub/*] { puts $fo "[get_attribute $p lib_pin_name] [get_attribute $p pin_direction]" }
close $fo
puts "R9B hub pins [sizeof_collection [get_pins u_hub/*]]"
set fo [open $W/hub_clk.txt w]
foreach_in_collection p [get_pins u_hub/*] {
    set n [get_nets -quiet -of_objects $p]
    if {[sizeof_collection $n] == 0} continue
    set d [get_pins -quiet -leaf -of_objects $n -filter "pin_direction==out"]
    foreach_in_collection q $d {
        if {[regexp {^(CKLN|CKBD|CKND)} [get_attribute [get_cells -of_objects $q] ref_name]]} { puts $fo "[get_attribute $p lib_pin_name] [get_object_name $q]" }
    }
}
close $fo
# characterize (QB_CHAR 1, default off): DC context budget; R9b uses its own IO budget (impl/r9b/budget.tcl) instead,
# because the column ETM outlier arcs (results/r8a.md) give characterize input delays of up to 370 ns
if {[qc_env QB_CHAR 0]} {
    characterize -constraints [get_cells u_hub]
    current_design qb_hub
    write_sdc -nosplit $W/qb_hub_char.sdc
}
current_design qb_hub
write -format verilog -hierarchy -output $W/qb_hub.v
puts "R9B hub ports [sizeof_collection [get_ports *]] in [sizeof_collection [all_inputs]] out [sizeof_collection [all_outputs]]"
set_svf -off
exit
