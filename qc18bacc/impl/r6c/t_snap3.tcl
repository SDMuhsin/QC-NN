# impl/r6c test of snap3.tcl (read-only on db/place.odb): 2000 repair buffers moved to random points inside the
# column array, snap3, then counts how many landed on a row bin and the mean move.
proc qb_env {n d} { return [expr {[info exists ::env($n)] ? $::env($n) : $d}] }
proc qc_log {m} { puts "QC_PNR $m" }
read_db $::env(QB_RUN)/db/place.odb
source $::env(QB_R6C)/snap3.tcl
set blk [ord::get_db_block]
set ax1 1e18; set ay1 1e18; set ax2 -1e18; set ay2 -1e18
foreach i [$blk getInsts] { if {[[$i getMaster] getName] eq "qb_col_blk"} { set b [$i getBBox]; set ax1 [expr {min($ax1,[$b xMin])}]; set ay1 [expr {min($ay1,[$b yMin])}]; set ax2 [expr {max($ax2,[$b xMax])}]; set ay2 [expr {max($ay2,[$b yMax])}] } }
expr {srand(3)}
set t {}
foreach i [$blk getInsts] { if {[llength $t] < 2000 && [string match wire* [$i getName]]} { $i setLocation [expr {round($ax1 + rand() * ($ax2 - $ax1))}] [expr {round($ay1 + rand() * ($ay2 - $ay1))}]; lappend t $i } }
qb6_snap
lassign [qb6c_rowbins] bx rh cx0 cy0
set on 0; set east 0
foreach i $t { lassign [$i getLocation] x y; if {[info exists ::QB6C_RB([expr {($x - $cx0) / $bx}],[expr {($y - $cy0) / $rh}])]} { incr on }; if {$x >= $ax2} { incr east } }
puts "T_SNAP3 moved [llength $t] on_row $on east_of_array $east"
