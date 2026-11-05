# Electrical repair before CTS (PRE_CTS_TCL; the place step runs with REPAIR_DESIGN 0).  Same scheme as
# impl/kulcluster/pnr/pre_cts.tcl.  Design rules are the ones DC met: max_transition 0.4 ns and max_fanout 16 from
# the DC SDC, max_capacitance from the liberty pins.  With placement RC (ss) about 77k pins violate slew, 9k cap and
# 1.7k fanout (rst_ni: 67k loads, an ideal network in DC).  repair_design of this OpenROAD build (2.0-12381) also
# resizes every driver it visits towards the library target slew: run plainly on this design it resized 1.09M of
# 1.36M instances and detailed placement did not finish in 50 min.  So: (1) only nets that violate a rule are
# repaired, all other signal nets are dont_touch during repair_design (DC's sizing kept); (2) logic cells may be
# resized up to drive SN_REPAIR_MAX_DRIVE (4), buffers / inverters up to D16; (3) the placement is re-spread with
# the new cell sizes (incremental global placement) and legalised.  Remaining sizing is left to repair_timing.
set sn_big {}
foreach c [get_lib_cells *] {
    set n [get_name $c]
    if {[regexp {^(BUFF|INV)D(\d+)$} $n -> k drv]} {
        if {$drv > 16} { lappend sn_big $n }
    } elseif {[regexp {D(\d+)$} $n -> drv] && $drv > [p SN_REPAIR_MAX_DRIVE 4]} { lappend sn_big $n }
}
set sn_big [lsort -unique $sn_big]
qc_log "repair_design: [llength $sn_big] large cells dont_use"
set_dont_use $sn_big
estimate_parasitics -placement
# nets with a DRV violation (any corner): pins of the violator report -> nets
set rf $::OUT/rpt/pre_cts.drv_before.rpt
qc_to $rf { report_check_types -max_slew -max_capacitance -max_fanout -violators }
set blk [ord::get_db_block]
array unset sn_vnet
set f [open $rf]
while {[gets $f line] >= 0} {
    if {![string match *VIOLATED* $line]} { continue }
    set pin [lindex $line 0]
    set k [string last / $pin]
    if {$k < 0} { set bt [$blk findBTerm $pin]; if {$bt ne "NULL" && [$bt getNet] ne "NULL"} { set sn_vnet([[$bt getNet] getName]) 1 }; continue }
    set inst [$blk findInst [string range $pin 0 [expr {$k - 1}]]]
    if {$inst eq "NULL"} { continue }
    set it [$inst findITerm [string range $pin [expr {$k + 1}] end]]
    if {$it ne "NULL" && [$it getNet] ne "NULL"} { set sn_vnet([[$it getNet] getName]) 1 }
}
close $f
file delete $rf
set sn_dt {}
foreach net [$blk getNets] {
    if {[$net getSigType] ne "SIGNAL" || [$net isSpecial] || [$net isDoNotTouch]} { continue }
    if {![info exists sn_vnet([$net getName])]} { $net setDoNotTouch 1; lappend sn_dt $net }
}
qc_log "repair_design: [array size sn_vnet] nets with DRV violations, [llength $sn_dt] nets dont_touch"
repair_design -max_utilization [p MAX_UTIL]
foreach net $sn_dt { $net setDoNotTouch 0 }
unset sn_dt; array unset sn_vnet
unset_dont_use $sn_big
set_dont_use $::QC_PNR_DONT_USE
qc_summary "repair_design [qc_util]"
# target density for the grown cell area: (cells + padding) / row area + 5 %, at least PLACE_DENSITY
set ra 0.0; set ca 0.0; set n 0
foreach r [$blk getRows] { set bb [$r getBBox]; set ra [expr {$ra + double([$bb dx]) * [$bb dy]}] }
set sw [[[lindex [$blk getRows] 0] getSite] getWidth]; set sh [[[lindex [$blk getRows] 0] getSite] getHeight]
foreach i [$blk getInsts] {
    set m [$i getMaster]
    if {![$m isBlock]} { set ca [expr {$ca + double([$m getWidth]) * [$m getHeight]}]; incr n }
}
set dens [expr {max([p PLACE_DENSITY], 0.05 + ($ca + $n * 2.0 * [p SN_INCR_PAD 0] * $sw * $sh) / $ra)}]
qc_log [format "incremental placement: cells %.3f of the row area, density %.3f" [expr {$ca / $ra}] $dens]
if {$dens > 0.95} { error "repair_design: cell area too large for the floorplan (density $dens)" }
global_placement -incremental -density $dens -pad_left [p SN_INCR_PAD 0] -pad_right [p SN_INCR_PAD 0]
detailed_placement
check_placement
estimate_parasitics -placement
qc_summary "pre_cts [qc_util]"
qc_summary "pre_cts [join [qc_timing_lines pre_cts] { | }]"
# report_clock_skew (cts.tcl) of this OpenROAD build walks the clock fanout per sink pair (sta::ClkSkews::
# findClkSkewFrom): on 170k sinks / 6.5k gated clock nets it was still running after 45 min.  Replaced by a note;
# the post-route skew comes from PrimeTime (pt_power.tcl, report_clock_timing -type skew).
if {[llength [info commands sn_report_clock_skew_orig]] == 0} { rename report_clock_skew sn_report_clock_skew_orig }
proc report_clock_skew {args} { puts "report_clock_skew skipped for run time (impl/snitch_cluster/pnr/pre_cts.tcl)" }
