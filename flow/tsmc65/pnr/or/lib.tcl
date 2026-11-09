# Shared Tcl of the OpenROAD P&R flow: configuration, library / design loading, RC, checkpoints, reports.
# Design settings live in ::P (per-design config, pnr/designs/*.cfg); kit settings in site/{site,pnr}.tcl.
set ::QC_FLOW $::env(QC_FLOW)
source $::QC_FLOW/site/site.tcl
source $::QC_FLOW/site/pnr.tcl

proc qc_env {name {default ""}} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $default
}
# p <key>: design setting (error if unset and no default)
proc p {key {default __none__}} {
    if {[info exists ::P($key)] && ($::P($key) ne "" || $default eq "__none__")} { return $::P($key) }
    if {$default ne "__none__"} { return $default }
    error "pnr config: $key not set"
}
proc qc_log {msg} { puts "QC_PNR $msg"; flush stdout }

# ---- defaults of every design setting (a design config overrides any of them)
array set ::P_DEFAULT {
    CORE_UTIL 0.55   ASPECT 1.0   CORE_MARGIN 5.0   DIE_AREA {}   CORE_AREA {}
    PLACE_DENSITY {}  PLACE_PAD 1   TIMING_DRIVEN 1   ROUTABILITY_DRIVEN 1   GPL_ARGS {}   DPL_ARGS {}
    PIN_TCL {}  FLOORPLAN_TCL {}  PRE_PLACE_TCL {}  PRE_CTS_TCL {}  PRE_ROUTE_TCL {}  POST_GRT_TCL {}  POST_ROUTE_TCL {}
    MACRO_LEFS {}  MACRO_LIBS_ss {}  MACRO_LIBS_tt {}  MACRO_LIBS_ff {}  MACRO_GDS {}
    MACRO_PLACE {}  MACRO_HALO {5 5}  MACRO_AUTO 1  MACRO_PDN_TCL {}  MACRO_PIN_LAYER M4
    PDN_TCL {}  PDN_RAIL_W 0.33
    PDN_V_LAYER M4  PDN_V_W 0.4  PDN_V_PITCH 20.0  PDN_V_OFFSET 2.0
    PDN_H_LAYER M7  PDN_H_W 0.8  PDN_H_PITCH 30.0  PDN_H_OFFSET 5.0
    CTS_CLUSTER_SIZE 20  CTS_CLUSTER_DIAMETER 50  CTS_ARGS {}
    SETUP_MARGIN 0.0  HOLD_MARGIN 0.02  REPAIR_DESIGN auto  REPAIR_TIMING 1  MAX_UTIL 85
    GR_ADJUST 0.3  GR_ITER 50  DR_END_ITER 64  DR_ARGS {}  ANTENNA_ITER 3  ANTENNA_CHECK 1
    FILL 1  DCAP 1  GDS 1
}
# Netlist / SDC: NETLIST and SDC, else <SYN>/<TOP>.v / .sdc where SYN is a synthesis run dir or a tag under
# $QC_BUILD/syn (env QC_PNR_SYN overrides SYN).  Env QC_PNR_SET = Tcl list {KEY VALUE ...} overrides the config.
proc qc_config {} {
    foreach {k v} [qc_env QC_PNR_SET] { set ::P($k) $v }
    foreach {k v} [array get ::P_DEFAULT] { if {![info exists ::P($k)]} { set ::P($k) $v } }
    set syn [qc_env QC_PNR_SYN [p SYN ""]]
    if {$syn ne "" && ![file isdirectory $syn]} { set syn $::env(QC_BUILD)/syn/$syn }
    if {[p NETLIST ""] eq ""} { set ::P(NETLIST) $syn/[p TOP].v }
    if {[p SDC ""] eq ""}     { set ::P(SDC) $syn/[p TOP].sdc }
    if {$::P(PLACE_DENSITY) eq ""} { set ::P(PLACE_DENSITY) [expr {min(0.92, [p CORE_UTIL] + 0.2)}] }
}

# ---- libraries, tech, design
proc qc_lib_file {corner} { return $::QC_PNR_LIBDIR/$::QC_LIB($corner)$::QC_PNR_LIBEXT }
proc qc_read_liberty {} {
    define_corners {*}$::QC_CORNERS
    foreach c $::QC_CORNERS {
        read_liberty -corner $c [qc_lib_file $c]
        foreach m [p MACRO_LIBS_$c] { read_liberty -corner $c $m }
    }
}
# tech LEF as read by OpenROAD: the kit LEF, or a copy without the MINIMUMCUT rules of QC_PNR_LEF_NO_MINCUT
proc qc_router_lef {} {
    if {![info exists ::QC_PNR_LEF_NO_MINCUT] || $::QC_PNR_LEF_NO_MINCUT eq ""} { return $::QC_PNR_LEF }
    set lef $::OUT/rc/[file tail $::QC_PNR_LEF]
    file mkdir $::OUT/rc
    if {![file exists $lef]} {
        qc_log [exec $::env(QC_PY) -I $::QC_FLOW/pnr/py/lef_pnr.py $::QC_PNR_LEF $lef {*}$::QC_PNR_LEF_NO_MINCUT]
    }
    return $lef
}
# macro LEF as read by OpenROAD: CLASS RING (ARM memory compilers with power rings) becomes CLASS BLOCK in a copy
# under $OUT/rc, else OpenROAD does not see the macro as a block (macro placement, cut_rows, pdngen macro grids)
proc qc_macro_lef {lef} {
    set f [open $lef]; set t [read $f]; close $f
    if {![regsub -all {(\n\s*CLASS\s+)RING(\s*;)} $t {\1BLOCK\2} t]} { return $lef }
    file mkdir $::OUT/rc
    set out $::OUT/rc/[file tail $lef]
    set f [open $out w]; puts -nonewline $f $t; close $f
    qc_log "macro LEF $lef: CLASS RING read as CLASS BLOCK ($out)"
    return $out
}
proc qc_read_libs {} {
    qc_read_liberty
    read_lef [qc_router_lef]
    foreach l [p MACRO_LEFS] { read_lef [qc_macro_lef $l] }
}
proc qc_read_design {} {
    read_verilog [p NETLIST]
    link_design [p TOP]
    set_dont_use $::QC_PNR_DONT_USE
}
proc qc_read_sdc {} { read_sdc [p SDC] }

# Per-corner wire RC from the captables (written by run_pnr.sh to $OUT/rc/<corner>.tcl), plus the RC per unit
# length used for pre-route estimates (set_wire_rc: QC_PNR_EST_SIGNAL / _CLOCK layer values of that corner).
proc qc_set_rc {} {
    file mkdir $::OUT/rc
    foreach c $::QC_CORNERS {
        if {![file exists $::OUT/rc/$c.tcl]} {
            exec $::env(QC_PY) -I $::QC_FLOW/pnr/py/captable_rc.py $::QC_PNR_LEF \
                $::QC_PNR_CAPDIR/$::QC_PNR_CAPTABLE($c) $c $::OUT/rc/$c
        }
        source $::OUT/rc/$c.tcl
        foreach {kind layer} [list -signal $::QC_PNR_EST_SIGNAL -clock $::QC_PNR_EST_CLOCK] {
            set f [open $::OUT/rc/$c.txt]; set r ""; set cap ""
            foreach line [split [read $f] \n] {
                if {[lindex $line 0] eq $layer} { set r [lindex $line 2]; set cap [lindex $line 3] }
            }
            close $f
            set_wire_rc $kind -corner $c -resistance [expr {$r / 1000.0}] -capacitance [expr {$cap / 1000.0}]
        }
    }
}

# Constant nets of the netlist (DC writes 1'b0 / 1'b1; OpenROAD links them as driverless n_Logic0_ / n_Logic1_):
# drive each with a tie cell, repair_tie_fanout later gives every load its own tie cell.
proc qc_tie_constants {} {
    set block [ord::get_db_block]
    set n 0
    foreach net [$block getNets] {
        set name [$net getName]
        if {[regexp {Logic([01])_?$} $name -> v]} {
            set drv 0
            foreach it [$net getITerms] { if {[$it isOutputSignal]} { set drv 1 } }
            if {$drv || [llength [$net getBTerms]]} { continue }
            set tie [expr {$v ? $::QC_PNR_TIEHI : $::QC_PNR_TIELO}]
            set m [[ord::get_db] findMaster [lindex $tie 0]]
            set inst [odb::dbInst_create $block $m qc_tie_[incr n]]
            [$inst findITerm [lindex $tie 1]] connect $net
        }
    }
    qc_log "tie cells for constant nets: $n"
}

# ---- checkpoints: every step ends with $OUT/db/<step>.odb (+ .sdc), QC_PNR_FROM=<step> restarts there
proc qc_save {step} {
    file mkdir $::OUT/db
    write_db $::OUT/db/$step.odb
    write_sdc $::OUT/db/$step.sdc
    qc_log "step $step done ([expr {[clock seconds] - $::T0}] s)"
}
proc qc_load {step} {
    qc_read_liberty
    read_db $::OUT/db/$step.odb
    set_dont_use $::QC_PNR_DONT_USE
    read_sdc $::OUT/db/$step.sdc
    qc_set_rc
    if {[lsearch $::STEPS $step] >= [lsearch $::STEPS cts]} { set_propagated_clock [all_clocks] }
}

# ---- reports
# qc_to <file> <script>: run script with its report output redirected to file
proc qc_to {file script} {
    sta::redirect_file_begin $file
    set rc [catch {uplevel 1 $script} msg]
    sta::redirect_file_end
    if {$rc} { qc_log "report to $file failed: $msg" }
}
proc qc_report {stage} {
    set f $::OUT/rpt/$stage
    file mkdir $::OUT/rpt
    qc_to $f.area.rpt { report_design_area }
    foreach c $::QC_CORNERS {
        qc_to $f.$c.max.rpt {
            report_checks -corner $c -path_delay max -format full_clock_expanded -fields {slew cap fanout} -digits 3
        }
        qc_to $f.$c.min.rpt { report_checks -corner $c -path_delay min -format full_clock_expanded -digits 3 }
    }
    qc_to $f.drv.rpt { report_check_types -max_slew -max_capacitance -max_fanout -violators }
}
# one line per corner: setup / hold worst slack and TNS (ns; STA internal unit is s) at the current parasitics
proc qc_timing_lines {stage} {
    set out {}
    foreach c $::QC_CORNERS {
        set ws [sta::worst_slack_corner [sta::find_corner $c] max]
        set wh [sta::worst_slack_corner [sta::find_corner $c] min]
        set ts [sta::total_negative_slack_corner_cmd [sta::find_corner $c] max]
        set th [sta::total_negative_slack_corner_cmd [sta::find_corner $c] min]
        lappend out [format "%s_%s setup_wns_ns %.3f setup_tns_ns %.3f hold_wns_ns %.3f hold_tns_ns %.3f" \
            $stage $c [expr {$ws * 1e9}] [expr {$ts * 1e9}] [expr {$wh * 1e9}] [expr {$th * 1e9}]]
    }
    return $out
}
proc qc_macros {} {
    set l {}
    foreach inst [[ord::get_db_block] getInsts] { if {[[$inst getMaster] isBlock]} { lappend l $inst } }
    return $l
}
proc qc_util {} {
    set block [ord::get_db_block]
    set core [$block getCoreArea]
    set ca [expr {double([$core dx]) * [$core dy]}]
    set sa 0.0; set ma 0.0
    foreach inst [$block getInsts] {
        set m [$inst getMaster]
        if {[$m getType] eq "CORE_SPACER" || [string match FILL* [$m getName]] || [string match DCAP* [$m getName]]} { continue }
        set a [expr {double([$m getWidth]) * [$m getHeight]}]
        if {[$m isBlock]} { set ma [expr {$ma + $a}] } else { set sa [expr {$sa + $a}] }
    }
    set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set die [$block getDieArea]
    return [format "die_um %.2f x %.2f core_um2 %.1f cell_um2 %.1f macro_um2 %.1f utilisation %.3f" \
        [expr {[$die dx] / double($u)}] [expr {[$die dy] / double($u)}] [expr {$ca / $u / $u}] \
        [expr {$sa / $u / $u}] [expr {$ma / $u / $u}] [expr {($sa + $ma) / $ca}]]
}
proc qc_summary {line} {
    set f [open $::OUT/summary.txt a]; puts $f $line; close $f
    qc_log $line
}
# Electrical repair of the nets with a max slew / cap / fanout violation only.  repair_design (build 2.0-12381)
# also resizes the driver of every net it visits towards its library target slew: on a DC-sized netlist that
# changes most instances (Snitch FPU: 75k of 96k, +80-90 % area) and loses timing.  All other signal nets are
# dont_touch while it runs, so DC's sizing is kept there; setup / hold sizing is left to repair_timing.
proc qc_repair_drv {} {
    set blk [ord::get_db_block]
    set rf $::OUT/rpt/drv_repair.tmp
    qc_to $rf { report_check_types -max_slew -max_capacitance -max_fanout -violators }
    array set v {}
    set f [open $rf]
    while {[gets $f line] >= 0} {
        if {![string match *VIOLATED* $line]} { continue }
        set pin [lindex $line 0]; set k [string last / $pin]
        set it NULL
        if {$k < 0} {
            set it [$blk findBTerm $pin]
        } elseif {[set i [$blk findInst [string range $pin 0 [expr {$k - 1}]]]] ne "NULL"} {
            set it [$i findITerm [string range $pin [expr {$k + 1}] end]]
        }
        if {$it ne "NULL" && [$it getNet] ne "NULL"} { set v([[$it getNet] getName]) 1 }
    }
    close $f
    file delete $rf
    set dt {}
    foreach n [$blk getNets] {
        if {[$n getSigType] ne "SIGNAL" || [$n isDoNotTouch] || [info exists v([$n getName])]} { continue }
        $n setDoNotTouch 1; lappend dt $n
    }
    qc_log "repair_design on [array size v] nets with DRV violations ([llength $dt] nets kept)"
    repair_design -max_utilization [p MAX_UTIL]
    foreach n $dt { $n setDoNotTouch 0 }
}
