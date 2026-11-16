# R8b PT hook (QC_PT_HOOK of flow/tsmc65/sta/run_pt.sh): impl/pt_hook.tcl + worst setup slack per act-supply endpoint
# class (S1 registers, S2 / act_q registers, line buffers, act pipe) and of the S1 paths from the line buffers.
source [file dirname [info script]]/../pt_hook.tcl
foreach {cls pat} {s1_reg {u_act/*u_s1/s1_reg*} s2_reg {u_act/u_s2/act_reg*} lb_reg {u_act/g_ctx_*/u_lb/*} pipe {u_act/g_pipe_*}} {
    set ep [filter_collection [all_registers -data_pins] "full_name =~ $pat"]
    if {![sizeof_collection $ep]} { puts $fh "r8b $cls no endpoints"; continue }
    set p [get_timing_paths -delay_type max -to $ep -max_paths 1]
    set s [get_attribute $p slack]
    puts $fh [format "r8b class %s endpoints %d worst_slack_ns %.3f fmax_mhz %.1f path %s -> %s" $cls [sizeof_collection $ep] $s \
        [expr {1000.0 / ($per - $s)}] [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
}
