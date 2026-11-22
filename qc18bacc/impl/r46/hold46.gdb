# R46: gdb batch script for the repair_timing -hold crash (impl/r46/hold46.tcl via impl/r29/or29.sh with
# R29_WRAP="gdb -batch -x <this> --args"): backtrace, faulting instruction, registers, and the code around it.
set pagination off
set confirm off
handle SIGSEGV stop print nopass
run
printf "R46_CRASH\n"
bt 10
x/i $pc
info registers
x/60i $pc-160
kill
quit
