# POST_GRT_TCL of impl/r14/top14.cfg (QB_GRT_STOP 1), GRT parasitics in memory:
#   clk14.tcl  effective clock skew table (rpt/clk14.txt, appended "grt")
#   drv_post   max slew / cap violators by class (block-only / trunk nets are checked here)
#   classes    impl/r11/classes.tcl twice: propagated (balanced) clock -> rpt/classes_tt_prop.txt; ideal clock with the
#              block insertion as clock latency (column -QB11_INS, hub -QB14_HINS, act -QB14_AINS) -> classes_tt_ideal.txt
#   then impl/r9b/post_grt.tcl (checkpoint db/grt.odb, exit)
foreach _f {clk14.tcl drv_post.tcl} { if {[file exists $::QB_R14/$_f]} { catch { source $::QB_R14/$_f } _e; qc_log "r14 $_f: $_e" } }
catch { q14_report $::OUT/rpt/clk14.txt grt } _e; qc_log "r14 clk report: $_e"
# re-balance at GRT parasitics (incremental GRT): QB14_BAL_GRT [1]
if {[qb_env QB14_BAL_GRT 1]} {
    set ::Q14_BAL_DEFONLY 1; source $::QB_R14/bal14.tcl
    if {[catch {
        global_route -start_incremental
        q14_balance [qb_env QB14_BAL_GRT_PASS 2] global_routing grt
        global_route -end_incremental
        estimate_parasitics -global_routing
        write_guides $::OUT/route.guide
        q14_report $::OUT/rpt/clk14.txt "grt after GRT-parasitics balancing"
    } _e]} { qc_log "r14 grt balance: $_e" }
}
if {[file exists $::QB_R11/classes.tcl]} {
    catch { source $::QB_R11/classes.tcl } _e; qc_log "r11 classes (propagated): $_e"
    catch { file rename -force $::OUT/rpt/classes_tt.txt $::OUT/rpt/classes_tt_prop.txt }
    catch {
        unset_propagated_clock [all_clocks]
        set_clock_latency [expr {-[qb_env QB11_INS 0.96]}] [get_pins u_top_u_core_u_arr_g_c_*__u_col/clk]
        set_clock_latency [expr {-[qb_env QB14_HINS 0.90]}] [get_pins u_hub/clk]
        set_clock_latency [expr {-[qb_env QB14_AINS 0.55]}] [get_pins u_act_blk/clk]
        source $::QB_R11/classes.tcl
        file rename -force $::OUT/rpt/classes_tt.txt $::OUT/rpt/classes_tt_ideal.txt
        set_propagated_clock [all_clocks]
    } _e
    qc_log "r11 classes (ideal + insertion latency): $_e"
}
source $::QB_R9B/post_grt.tcl
