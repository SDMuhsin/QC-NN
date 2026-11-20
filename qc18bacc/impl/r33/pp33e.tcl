# R33: delay spent in "clumped" repeaters on violating paths: a buffer stage whose output net has one load, a buffer
# input, and total net cap < 12 fF (i.e. the next buffer sits next to it)
set f [open $::env(R31_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
set io [add_to_collection [all_inputs] [all_outputs]]
proc clump {pins} {
  set n 0; set d 0.0; set prev ""; set prevt ""
  foreach_in_collection pt $pins {
    set p [get_attribute $pt object]; set a [get_attribute $pt arrival]
    if {[get_attribute -quiet $p object_class] ne "pin"} { set prev ""; continue }
    if {[get_attribute $p direction] eq "out"} {
      set c [get_cells -of $p]; set r [get_attribute $c ref_name]
      if {[regexp {^(BUFF|CKBD)} $r] && $prev ne ""} {
        set nl [get_nets -of $p]; set ld [get_pins -quiet -of $nl -filter "direction==in"]
        if {[sizeof_collection $ld] == 1 && [regexp {^(BUFF|CKBD)} [get_attribute [get_cells -of $ld] ref_name]]} {
          set cap [get_attribute -quiet $nl total_capacitance_max]
          if {$cap ne "" && $cap < 0.012} { incr n; set d [expr {$d + $a - $prevt}] }
        }
      }
      set prev ""
    } else { set prev $p; set prevt $a }
  }
  return [list $n $d]
}
foreach {k a} [list reg2reg [list -exclude $io] all {}] {
  set ps [get_timing_paths -delay_type max -max_paths 300 -nworst 1 -slack_lesser_than 0 {*}$a]
  set N 0; set D 0.0; set np 0; set mx 0.0; set worst ""
  foreach_in_collection p $ps { incr np; lassign [clump [get_attribute $p points]] n d; incr N $n; set D [expr {$D + $d}]; if {$d > $mx} { set mx $d }; if {$worst eq ""} { set worst "$n stages [format %.3f $d] ns" } }
  puts [format "R33E %s %s paths %d clumped stages %d (%.1f / path) delay %.3f ns / path, max %.3f; worst path: %s" $corner $k $np $N [expr {double($N)/max(1,$np)}] [expr {$D/max(1,$np)}] $mx $worst]
}
exit
