# IO budget of the regression block qb_lane_n: the column's budget procs (blocks/col/io_budget.tcl: input -max budget,
# -min = early clock arrival + fastest library clock -> Q, output -max / -min) with this block's port classes as
# fractions of the period (the column's north inputs / south outputs).  No act / act_o: no feedthrough, no act driving cell.
set ::QB5_BUDGET {
    in  {x[*] m[*] sh[*] h[*] r[*] t[*] vld mode} 0.30
    out {y_o[*] b_o vld_o}                        0.25
}
source [file join [file dirname [file normalize [info script]]] .. col io_budget.tcl]
