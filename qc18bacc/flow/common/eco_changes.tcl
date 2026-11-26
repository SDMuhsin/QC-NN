# PrimeTime change list (write_changes -format icc2tcl, <run>/out/eco/pt_eco.tcl) as both tools read it (R90): PrimeTime
# writes the record of its new cells (signoff/pt/drv_eco.tcl), ICC2 sources the list and checks it (flow/icc2/common.tcl
# qb_eco_names).  Sourced by both; only commands both tools have.
#   qb_eco_lines <chg>          the command lines of the list (blank and '#' lines dropped)
#   qb_eco_parse <line> <sc>    one line under current_instance <sc> ("" = top) -> {kind fields}, every name made full
#                               (<sc>/<name>):  scope {sc} | size {cell ref} | loc {cell} | ins {pin|port obj ref net cell}
#                               | abor {pin cell ref [cell ref ...]} (add_buffer_on_route: one cell / ref pair per buffer
#                               of -user_specified_buffers; PT gives the buffer's leaf name, made full under <sc>; the
#                               block is flat since R91, flow/icc2 qb_flatten) | unparsed {}
#   qb_eco_abor <line>          add_buffer_on_route line -> {pin buffers}: driver pin as written, PT's -user_specified_buffers
#                               text {name lib_cell x y layer ...}; {} if the line is not a well-formed one
#   qb_eco_new_cells <chg>      the cells the list creates: {full ref}
#   qb_eco_loads <cell>         sorted full names of the loads the cell's outputs drive: leaf input pins and output
#                               ports (R92: without the ports a buffer driving an output port had the record {} in both
#                               tools, r91b U_PTECO_DRC_BUF20, and the PT-vs-ICC2 load comparison compared nothing);
#                               error if there is none
#   qb_eco_cells_file <chg>     the new-cell record next to the list: <chg root>_cells.txt, one Tcl list per cell
#                               {full_name ref_name loads} as the writing tool (PrimeTime) has the cell
proc qb_eco_lines {chg} {
    set fh [open $chg]; set t [read $fh]; close $fh
    set r {}
    foreach l [split $t "\n"] { set l [string trim $l]; if {$l ne "" && [string index $l 0] ne "#"} { lappend r $l } }
    return $r
}
proc qb_eco_full {sc x} { expr {$sc eq "" ? $x : "$sc/$x"} }
proc qb_eco_parse {l sc} {
    if {$l eq "current_instance"} { return [list scope [list ""]] }
    if {[regexp {^current_instance \{([^\}]*)\}$} $l -> s]} { return [list scope [list $s]] }
    if {[regexp {^size_cell \{([^\}]*)\} \{([^\}]*)\}$} $l -> c r]} { return [list size [list [qb_eco_full $sc $c] [file tail $r]]] }
    if {[regexp {^set_cell_location .*\[get_cells \{([^\}]*)\} ?\]$} $l -> c]} { return [list loc [list [qb_eco_full $sc $c]]] }
    if {[regexp {^insert_buffer \[get_(pins|ports) \{([^\}]*)\}\] (\S+) -new_net_names \{([^\}]*)\} -new_cell_names \{([^\}]*)\}} $l -> ty p r nn c]} {
        return [list ins [list [string range $ty 0 end-1] [qb_eco_full $sc $p] [file tail $r] [qb_eco_full $sc $nn] [qb_eco_full $sc $c]]]
    }
    if {[llength [set a [qb_eco_abor $l]]]} {
        lassign $a p b
        set f [list [qb_eco_full $sc $p]]
        foreach {c r x y ly} $b { lappend f [qb_eco_full $sc $c] [file tail $r] }
        return [list abor $f]
    }
    return [list unparsed {}]
}
proc qb_eco_abor {l} {
    if {![regexp {^add_buffer_on_route \[get_net -of \{([^\}]*)\}\] -user_specified_buffers \{([^\}]*)\}} $l -> p b]} { return {} }
    # every buffer of the list: {name lib_cell x y layer} each (R92: only the first was parsed)
    if {[catch {llength $b} nb] || !$nb || $nb % 5} { return {} }
    return [list $p $b]
}
proc qb_eco_new_cells {chg} {
    set sc ""; set r {}
    foreach l [qb_eco_lines $chg] {
        lassign [qb_eco_parse $l $sc] k f
        switch $k {
            scope { set sc [lindex $f 0] }
            ins   { lassign $f ty o ref nn c; lappend r [list $c $ref] }
            abor  { foreach {c ref} [lrange $f 1 end] { lappend r [list $c $ref] } }
        }
    }
    return $r
}
proc qb_eco_loads {c} {
    set n [get_nets -quiet -of_objects [get_pins -quiet -of_objects $c -filter "direction==out"]]
    set l {}
    if {[sizeof_collection $n]} {
        set n [get_nets -quiet -segments $n]
        set l [concat [get_object_name [get_pins -quiet -leaf -of_objects $n -filter "direction==in"]] \
            [get_object_name [get_ports -quiet -of_objects $n -filter "direction==out"]]]
    }
    if {![llength $l]} { error "qb_eco_loads: [get_object_name $c] drives no leaf input pin and no output port (an empty load record compares nothing)" }
    return [lsort -unique $l]
}
proc qb_eco_cells_file {chg} { return [file rootname $chg]_cells.txt }
