# R46: gdb batch script for the repair_antennas crash (impl/r46/ant46.tcl via impl/r29/or29.sh with
# R29_WRAP="gdb -batch -x <this> --args").  Records the net and GRT route of every grt::RepairAntennas::makeNetWire call
# (net = $rsi, route = $rdx at entry; GSegment = 6 ints) and prints the last one at the SIGSEGV.
set pagination off
set confirm off
handle SIGSEGV stop print nopass
tbreak grt::RepairAntennas::makeNetWires
run
break grt::RepairAntennas::makeNetWire
commands
silent
set $n = $rsi
set $r = $rdx
continue
end
continue
printf "R46_CRASH\n"
bt 12
set $nm = ((char*(*)(void*))'odb::dbNet::getConstName')($n)
printf "R46_NET %s\n", $nm
set $p = (int*)*(long*)$r
set $e = (int*)*((long*)$r + 1)
while $p < $e
  printf "R46_SEG %d %d %d %d %d %d\n", $p[0], $p[1], $p[2], $p[3], $p[4], $p[5]
  set $p = $p + 6
end
kill
quit
