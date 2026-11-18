# R25 (results/r25.md): impl/r24/cls24.tcl (imported: R21_CLS classes + R24_GRP, its qb24_stem grouping) and then
#   R25_GRP   every reg2reg start -> end group with worst slack < 0: endpoints, worst, and for the worst path the logic
#             comb cells (between launch and capture), buffers / inverters, max net fanout, and whether a cell or net
#             on it matches (^|_|/)(pt|lgw|pop|b2)_ (param table lookup); R25_PATH: cell sequence of the 3 worst groups
#   R25_HIST  reg2reg endpoint slack histogram, 0.1 ns bins (all reg2reg endpoints with slack < QB25_HMAX [2.0])
rename exit qb25_exit
proc exit {args} {}
source $::env(QC_FLOW)/../../qc18bacc/impl/r24/cls24.tcl
proc qb25_delay {pe} {
    # R25_DELAY: data-path delay of the path split into net (input-pin arrival steps), buffer / inverter cell, logic cell
    set prev ""; array set D {net 0 buf 0 logic 0 launch 0}; set a0 ""
    foreach p [get_property $pe points] {
        set pin [get_property $p pin]; set a [get_property $p arrival]
        if {$prev ne ""} {
            set d [expr {$a - $prev}]; set ob [$pin instance]
            if {[get_property $pin direction] eq "input"} { set c net } elseif {$a0 eq ""} { set c launch } elseif {[regexp {^(BUF|INV|CKB|CKN|DEL)} [get_property $ob ref_name]]} { set c buf } else { set c logic }
            if {$c ne "net" && $a0 eq ""} { set a0 $a }
            set D($c) [expr {$D($c) + $d}]
        }
        set prev $a
    }
    puts "R25_DELAY launch_clk_to_q+clk [format %.3f $D(launch)] net [format %.3f $D(net)] buf_inv_cells [format %.3f $D(buf)] logic_cells [format %.3f $D(logic)] slack [format %.3f [get_property $pe slack]]"
}
proc qb25_fanin {pe} {
    # R25_FANIN: register stems in the fanin cone of each path stage output (get_fanin -startpoints_only); the first
    # stage whose cone contains a (^|_|/)(pt|lgw|pop|b2)_ register = where the param-table lookup joins the path
    set i 0; set first -; set all {}
    foreach p [get_property $pe points] {
        set pin [get_property $p pin]; if {[get_property $pin direction] ne "output"} continue
        incr i; set st {}
        foreach q [get_fanin -to $pin -startpoints_only -flat] { set k [qb24_stem $q]; if {[lsearch -exact $st $k] < 0} { lappend st $k } }
        foreach k $st { if {$first eq "-" && [regexp {(^|_|/)(pt|lgw|pop|b2)_} $k]} { set first "$i:$k" } }
        set all $st
    }
    puts "R25_FANIN stages $i first_param_stage $first cone_at_last_stage [llength $all] stems: [join [lrange [lsort $all] 0 30] { }]"
}
proc qb25_path {pe {show 0}} {
    # comb = cells strictly between launch and capture; pt = cells or nets on the path matching (^|_|/)(pt|lgw|pop|b2)_
    set cells {}; set pt {}; set nets {}; set maxfo 0; set seq {}
    foreach p [get_property $pe points] {
        set pin [get_property $p pin]; set ob [$pin instance]
        if {$ob eq "NULL" || $ob eq ""} continue
        set n [get_full_name $ob]
        if {[lsearch -exact $cells $n] < 0} { lappend cells $n; lappend seq "${n}([get_property $ob ref_name])" }
        if {[get_property $pin direction] eq "output"} {
            set nt [get_nets -quiet -of_objects $pin]
            if {[llength $nt]} { lappend nets [get_full_name $nt]
                set fo [llength [get_pins -quiet -of_objects $nt -filter "direction==input"]]; if {$fo > $maxfo} { set maxfo $fo } }
        }
    }
    set re {(^|_|/)(pt|lgw|pop|b2)_}
    foreach n [concat [lrange $cells 1 end-1] $nets] { if {[regexp $re $n]} { lappend pt $n } }
    set nb 0; foreach q [lrange $seq 1 end-1] { if {[regexp {\((BUF|INV|CKB|CKN|DEL)} $q]} { incr nb } }
    if {$show} { puts "R25_PATH [join $seq { > }]"; qb25_delay $pe; qb25_fanin $pe }
    return [list [expr {[llength $cells] - 2}] [llength $cells] [llength $pt] [lindex $pt 0] $nb $maxfo]
}
set hmax [expr {[info exists ::env(QB25_HMAX)] ? $::env(QB25_HMAX) : 2.0}]
set ps [find_timing_paths -path_delay max -group_count 10000000 -endpoint_count 1 -slack_max $hmax -from [all_registers] -to [all_registers]]
set ::qb25_i 0; array set H25 {}; array set G25 {}; array set W25 {}
foreach pe $ps {
    set s [get_property $pe slack]
    set b [expr {int(floor($s / 0.1))}]; if {[info exists H25($b)]} { incr H25($b) } else { set H25($b) 1 }
    if {$s >= 0} continue
    set k "[qb24_stem [get_property $pe startpoint]] -> [qb24_stem [get_property $pe endpoint]]"
    if {![info exists G25($k)]} { set G25($k) 0; set W25($k) [list $s $pe] }
    incr G25($k); if {$s < [lindex $W25($k) 0]} { set W25($k) [list $s $pe] }
}
puts "R25_N reg2reg endpoints with slack < $hmax: [llength $ps]; violating groups [array size G25]"
foreach b [lsort -integer [array names H25]] { puts "R25_HIST [format %.1f [expr {$b*0.1}]] $H25($b)" }
foreach k [lsort -command {apply {{a b} {expr {[lindex $::W25($a) 0] < [lindex $::W25($b) 0] ? -1 : 1}}}} [array names G25]] {
    lassign $W25($k) s pe; lassign [qb25_path $pe [expr {[incr ::qb25_i] <= 3}]] dep nc npt pt1 nb mfo
    puts "R25_GRP $k | endpoints $G25($k) worst [format %.3f $s] comb_cells $dep (buf/inv $nb) cells $nc max_fanout $mfo pt_hits $npt first_pt $pt1 | start [get_full_name [get_property $pe startpoint]] end [get_full_name [get_property $pe endpoint]]"
}
qb25_exit
